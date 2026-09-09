import 'package:flutter/foundation.dart';

import '../db/ledger_repository.dart';
import '../models/customer.dart';
import '../models/ledger_transaction.dart';
import '../models/shop.dart';
import '../models/trust_score.dart';
import '../services/extraction/transaction_draft.dart';
import '../services/scoring_service.dart';

/// Single source of truth for ledger state.
///
/// Deliberately a plain ChangeNotifier rather than a state-management package:
/// one screen graph, one data source, and no dependency to debug at 3am.
class LedgerController extends ChangeNotifier {
  LedgerController({
    LedgerRepository? repository,
    ScoringService scoring = const ScoringService(),
  })  : _repo = repository ?? LedgerRepository(),
        _scoring = scoring;

  final LedgerRepository _repo;
  final ScoringService _scoring;

  Shop? _shop;
  List<CustomerBalance> _balances = const [];
  List<LedgerTransaction> _allTransactions = const [];
  TrustScoreSnapshot? _score;
  LedgerStats? _stats;
  bool _loading = true;

  Shop? get shop => _shop;
  bool get isOnboarded => _shop != null;
  List<CustomerBalance> get balances => _balances;
  List<LedgerTransaction> get allTransactions => _allTransactions;
  TrustScoreSnapshot? get score => _score;
  LedgerStats? get stats => _stats;
  bool get loading => _loading;

  /// Names fed to the extractors so a spoken name resolves to an existing
  /// customer instead of creating a near-duplicate.
  List<String> get knownCustomerNames =>
      _balances.map((b) => b.customer.name).toList();

  double get totalOutstanding =>
      _balances.fold<double>(0, (sum, b) => sum + (b.balance > 0 ? b.balance : 0));

  /// Score is meaningful only above a few entries; the UI says so plainly.
  bool get scoreIsProvisional => _scoring.isProvisional(_allTransactions);

  Future<void> load() async {
    _loading = true;
    notifyListeners();

    _shop = await _repo.getShop();
    if (_shop == null) {
      _balances = const [];
      _allTransactions = const [];
      _score = null;
      _stats = null;
      _loading = false;
      notifyListeners();
      return;
    }

    await _refreshLedger();
    _loading = false;
    notifyListeners();
  }

  Future<void> _refreshLedger() async {
    final shopId = _shop!.id!;
    _balances = await _repo.getCustomerBalances(shopId);
    _allTransactions = await _repo.getAllTransactions(shopId);
    _stats = _scoring.statsFor(_allTransactions);
    _score = _scoring.compute(shopId: shopId, transactions: _allTransactions);
  }

  Future<void> completeOnboarding({
    required String shopName,
    required String ownerName,
    required String location,
  }) async {
    _shop = await _repo.saveShop(
      Shop(
        name: shopName.trim(),
        ownerName: ownerName.trim(),
        location: location.trim(),
        createdAt: DateTime.now(),
      ),
    );
    await _refreshLedger();
    notifyListeners();
  }

  /// Saves a confirmed draft, resolving or creating the customer.
  Future<LedgerTransaction> saveDraft(TransactionDraft draft) async {
    final shop = _shop;
    if (shop == null) throw StateError('No shop profile');
    if (!draft.isComplete) {
      throw StateError('Draft is missing: ${draft.missingFields.join(', ')}');
    }

    final customer = await _repo.resolveOrCreateCustomer(
      shop.id!,
      draft.customerName!,
    );
    final saved = await _repo.addTransaction(draft.toTransaction(customer.id!));

    await _refreshLedger();
    notifyListeners();
    return saved;
  }

  /// Batch save from the camera-scan flow. Returns how many rows were written.
  Future<int> saveDrafts(List<TransactionDraft> drafts) async {
    final shop = _shop;
    if (shop == null) throw StateError('No shop profile');

    final complete = drafts.where((d) => d.isComplete).toList();
    if (complete.isEmpty) return 0;

    // Customers are resolved one at a time (each may need an insert) before
    // the transactions go in as a single batch.
    final transactions = <LedgerTransaction>[];
    for (final draft in complete) {
      final customer = await _repo.resolveOrCreateCustomer(
        shop.id!,
        draft.customerName!,
      );
      transactions.add(draft.toTransaction(customer.id!));
    }

    final count = await _repo.addTransactions(transactions);
    await _refreshLedger();
    notifyListeners();
    return count;
  }

  Future<List<LedgerTransaction>> transactionsFor(int customerId) =>
      _repo.getTransactionsForCustomer(customerId);

  Future<Customer?> customer(int id) => _repo.getCustomer(id);

  Future<void> deleteTransaction(int id) async {
    await _repo.deleteTransaction(id);
    await _refreshLedger();
    notifyListeners();
  }

  /// Persists the current score so the passport has a dated snapshot to show.
  Future<TrustScoreSnapshot?> persistScoreSnapshot() async {
    final current = _score;
    if (current == null) return null;
    final saved = await _repo.saveSnapshot(current);
    _score = saved;
    notifyListeners();
    return saved;
  }
}
