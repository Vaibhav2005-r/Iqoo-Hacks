import 'package:sqflite/sqflite.dart';

import '../models/customer.dart';
import '../models/ledger_transaction.dart';
import '../models/shop.dart';
import '../models/trust_score.dart';
import 'app_database.dart';

/// All ledger reads and writes. Kept as one repository rather than four DAOs —
/// at this scale the extra indirection would cost more than it buys.
class LedgerRepository {
  LedgerRepository({AppDatabase? db}) : _appDb = db ?? AppDatabase.instance;

  final AppDatabase _appDb;

  Future<Database> get _db => _appDb.database;

  // --- Shop ----------------------------------------------------------------

  /// The one and only shop profile, or null before onboarding.
  Future<Shop?> getShop() async {
    final db = await _db;
    final rows = await db.query('shops', orderBy: 'id ASC', limit: 1);
    if (rows.isEmpty) return null;
    return Shop.fromMap(rows.first);
  }

  Future<Shop> saveShop(Shop shop) async {
    final db = await _db;
    if (shop.id == null) {
      final id = await db.insert('shops', shop.toMap());
      return shop.copyWith(id: id);
    }
    await db.update(
      'shops',
      shop.toMap(),
      where: 'id = ?',
      whereArgs: [shop.id],
    );
    return shop;
  }

  // --- Customers -----------------------------------------------------------

  Future<Customer?> findCustomerByName(int shopId, String name) async {
    final db = await _db;
    final rows = await db.query(
      'customers',
      where: 'shop_id = ? AND name = ? COLLATE NOCASE',
      whereArgs: [shopId, name.trim()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Customer.fromMap(rows.first);
  }

  /// Resolve a spoken/OCR'd name to a customer row, creating one if needed.
  ///
  /// Exact (case-insensitive) match first, then a conservative fuzzy match so
  /// "Sharma ji" and "sharma" don't become two separate customers. Fuzzy
  /// matching is deliberately narrow — wrongly merging two real customers is
  /// worse than creating a duplicate the shopkeeper can see and fix.
  Future<Customer> resolveOrCreateCustomer(int shopId, String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) {
      throw ArgumentError('Customer name cannot be empty');
    }

    final exact = await findCustomerByName(shopId, name);
    if (exact != null) return exact;

    final fuzzy = await _findSimilarCustomer(shopId, name);
    if (fuzzy != null) return fuzzy;

    return createCustomer(
      Customer(shopId: shopId, name: name, createdAt: DateTime.now()),
    );
  }

  Future<Customer?> _findSimilarCustomer(int shopId, String name) async {
    final candidates = await getCustomers(shopId);
    final normalised = _normaliseName(name);
    if (normalised.isEmpty) return null;

    for (final c in candidates) {
      final other = _normaliseName(c.name);
      if (other.isEmpty) continue;
      // One name fully containing the other, on a word boundary, is the only
      // fuzzy case we accept ("sharma" vs "sharma ji").
      if (other == normalised) return c;
      if (_containsAsWords(other, normalised) ||
          _containsAsWords(normalised, other)) {
        return c;
      }
    }
    return null;
  }

  /// Strips honorifics and punctuation so "Sharma ji," == "sharma".
  static String _normaliseName(String name) {
    const honorifics = {
      'ji', 'jee', 'bhai', 'bhaiya', 'behen', 'didi', 'sahab', 'saheb',
      'shri', 'smt', 'mr', 'mrs', 'ms',
    };
    final words = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\sऀ-ॿ]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && !honorifics.contains(w))
        .toList();
    return words.join(' ');
  }

  static bool _containsAsWords(String haystack, String needle) {
    final hWords = haystack.split(' ');
    final nWords = needle.split(' ');
    if (nWords.isEmpty || nWords.length > hWords.length) return false;
    for (var i = 0; i + nWords.length <= hWords.length; i++) {
      if (hWords.sublist(i, i + nWords.length).join(' ') == needle) return true;
    }
    return false;
  }

  Future<Customer> createCustomer(Customer customer) async {
    final db = await _db;
    final id = await db.insert(
      'customers',
      customer.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return customer.copyWith(id: id);
  }

  Future<List<Customer>> getCustomers(int shopId) async {
    final db = await _db;
    final rows = await db.query(
      'customers',
      where: 'shop_id = ?',
      whereArgs: [shopId],
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(Customer.fromMap).toList();
  }

  Future<Customer?> getCustomer(int id) async {
    final db = await _db;
    final rows = await db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Customer.fromMap(rows.first);
  }

  /// Customers with running balances, computed in SQL in one pass.
  Future<List<CustomerBalance>> getCustomerBalances(int shopId) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT
        c.id, c.shop_id, c.name, c.phone, c.created_at,
        COALESCE(SUM(
          CASE WHEN t.direction = 'CREDIT' THEN t.amount ELSE -t.amount END
        ), 0) AS balance,
        COUNT(t.id) AS tx_count,
        MAX(t.created_at) AS last_activity
      FROM customers c
      LEFT JOIN transactions t ON t.customer_id = c.id
      WHERE c.shop_id = ?
      GROUP BY c.id
      ORDER BY balance DESC, c.name COLLATE NOCASE ASC
    ''', [shopId]);

    return rows.map((row) {
      final lastMs = row['last_activity'] as int?;
      return CustomerBalance(
        customer: Customer.fromMap(row),
        balance: (row['balance'] as num).toDouble(),
        transactionCount: (row['tx_count'] as num).toInt(),
        lastActivity: lastMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(lastMs),
      );
    }).toList();
  }

  // --- Transactions --------------------------------------------------------

  Future<LedgerTransaction> addTransaction(LedgerTransaction tx) async {
    final db = await _db;
    final id = await db.insert('transactions', tx.toMap());
    return tx.copyWith(id: id);
  }

  /// Batch insert for the camera-scan flow, in one SQLite transaction so a
  /// half-saved page is impossible.
  Future<int> addTransactions(List<LedgerTransaction> txs) async {
    if (txs.isEmpty) return 0;
    final db = await _db;
    return db.transaction<int>((txn) async {
      final batch = txn.batch();
      for (final tx in txs) {
        batch.insert('transactions', tx.toMap());
      }
      final results = await batch.commit(noResult: false);
      return results.length;
    });
  }

  Future<List<LedgerTransaction>> getTransactionsForCustomer(
    int customerId,
  ) async {
    final db = await _db;
    final rows = await db.query(
      'transactions',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(LedgerTransaction.fromMap).toList();
  }

  Future<List<LedgerTransaction>> getAllTransactions(int shopId) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT t.* FROM transactions t
      JOIN customers c ON c.id = t.customer_id
      WHERE c.shop_id = ?
      ORDER BY t.created_at DESC, t.id DESC
    ''', [shopId]);
    return rows.map(LedgerTransaction.fromMap).toList();
  }

  Future<double> getCustomerBalance(int customerId) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(
        CASE WHEN direction = 'CREDIT' THEN amount ELSE -amount END
      ), 0) AS balance
      FROM transactions WHERE customer_id = ?
    ''', [customerId]);
    return (rows.first['balance'] as num).toDouble();
  }

  Future<void> deleteTransaction(int id) async {
    final db = await _db;
    await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  // --- Score snapshots -----------------------------------------------------

  Future<TrustScoreSnapshot> saveSnapshot(TrustScoreSnapshot snapshot) async {
    final db = await _db;
    final id = await db.insert('score_snapshots', snapshot.toMap());
    return TrustScoreSnapshot(
      id: id,
      shopId: snapshot.shopId,
      score: snapshot.score,
      computedAt: snapshot.computedAt,
      components: snapshot.components,
    );
  }

  Future<TrustScoreSnapshot?> getLatestSnapshot(int shopId) async {
    final db = await _db;
    final rows = await db.query(
      'score_snapshots',
      where: 'shop_id = ?',
      whereArgs: [shopId],
      orderBy: 'computed_at DESC, id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return TrustScoreSnapshot.fromMap(rows.first);
  }
}
