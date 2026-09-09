import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// SQLite bootstrap. Single local database, no sync, no encryption
/// (encryption is a stated roadmap item — see README "Not built").
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const _dbName = 'khatasetu.db';
  static const _dbVersion = 1;

  Database? _db;

  Future<Database> get database async {
    return _db ??= await _open();
  }

  Future<Database> _open() async {
    final dbPath = p.join(await getDatabasesPath(), _dbName);
    return openDatabase(
      dbPath,
      version: _dbVersion,
      onConfigure: (db) async {
        // Cascade deletes rely on this; sqflite leaves FKs off by default.
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _createSchema,
    );
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE shops (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        owner_name TEXT NOT NULL,
        location TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shop_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        phone TEXT,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (shop_id) REFERENCES shops (id) ON DELETE CASCADE
      )
    ''');

    // Customer names are matched case-insensitively when resolving what the
    // shopkeeper said, so keep the uniqueness rule in the same shape.
    await db.execute('''
      CREATE UNIQUE INDEX idx_customers_shop_name
      ON customers (shop_id, name COLLATE NOCASE)
    ''');

    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        amount REAL NOT NULL,
        direction TEXT NOT NULL CHECK (direction IN ('CREDIT', 'PAYMENT')),
        item_description TEXT,
        source TEXT NOT NULL CHECK (source IN ('VOICE', 'CAMERA_SCAN', 'MANUAL')),
        created_at INTEGER NOT NULL,
        raw_input_ref TEXT,
        FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_tx_customer ON transactions (customer_id, created_at)',
    );
    await db.execute(
      'CREATE INDEX idx_tx_created ON transactions (created_at)',
    );

    await db.execute('''
      CREATE TABLE score_snapshots (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shop_id INTEGER NOT NULL,
        score REAL NOT NULL,
        computed_at INTEGER NOT NULL,
        inputs_json TEXT NOT NULL,
        FOREIGN KEY (shop_id) REFERENCES shops (id) ON DELETE CASCADE
      )
    ''');
  }

  /// Test/demo helper: wipe ledger rows but keep the shop profile.
  Future<void> clearLedger() async {
    final db = await database;
    await db.delete('transactions');
    await db.delete('customers');
    await db.delete('score_snapshots');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
