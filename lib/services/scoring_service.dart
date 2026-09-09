import 'dart:math' as math;

import '../models/ledger_transaction.dart';
import '../models/trust_score.dart';

/// Tuning constants for the trust score. Exposed as named constants so the
/// Credit Passport can state the targets out loud ("15 regular customers =
/// full marks") instead of presenting a number nobody can interrogate.
class ScoringConfig {
  const ScoringConfig({
    this.repaymentMax = 40,
    this.tenureMax = 20,
    this.customersMax = 20,
    this.velocityMax = 20,
    this.tenureTargetDays = 180,
    this.customerTarget = 15,
    this.velocityTargetTx = 40,
    this.velocityWindowDays = 30,
    this.minTransactionsForConfidence = 5,
  });

  final double repaymentMax;
  final double tenureMax;
  final double customersMax;
  final double velocityMax;

  /// Days of ledger history that earn full tenure marks.
  final int tenureTargetDays;

  /// Distinct active customers that earn full marks.
  final int customerTarget;

  /// Transactions inside [velocityWindowDays] that earn full marks.
  final int velocityTargetTx;
  final int velocityWindowDays;

  /// Below this many transactions the score is flagged provisional.
  final int minTransactionsForConfidence;

  static const ScoringConfig defaults = ScoringConfig();
}

/// Rule-based, fully transparent trust score.
///
/// Deliberately not ML: a shopkeeper being shown a number that decides their
/// loan eligibility should be able to be told exactly why it is what it is,
/// and what raises it. Every component returns its own plain-language
/// explanation, which the passport renders verbatim.
class ScoringService {
  const ScoringService({this.config = ScoringConfig.defaults, DateTime? now})
      : _fixedNow = now;

  final ScoringConfig config;

  /// Injectable clock, so tests aren't time-dependent.
  final DateTime? _fixedNow;

  DateTime get _now => _fixedNow ?? DateTime.now();

  /// True when there is too little history for the score to mean much.
  bool isProvisional(List<LedgerTransaction> txs) =>
      txs.length < config.minTransactionsForConfidence;

  TrustScoreSnapshot compute({
    required int shopId,
    required List<LedgerTransaction> transactions,
  }) {
    final components = <ScoreComponent>[
      _repaymentComponent(transactions),
      _tenureComponent(transactions),
      _customerComponent(transactions),
      _velocityComponent(transactions),
    ];

    final total = components.fold<double>(0, (sum, c) => sum + c.earned);

    return TrustScoreSnapshot(
      shopId: shopId,
      score: double.parse(total.clamp(0, 100).toStringAsFixed(1)),
      computedAt: _now,
      components: components,
    );
  }

  // --- Components ----------------------------------------------------------

  /// Repayment consistency, weighted by money rather than by transaction
  /// count.
  ///
  /// The spec sketched this as a ratio of PAYMENT to CREDIT *transactions*,
  /// but counts are trivially misleading: one 5,000 rupee udhar settled by one
  /// 10 rupee payment would score a perfect 1.0. Comparing rupees repaid
  /// against rupees extended is the measure a lender actually cares about, so
  /// that is what this uses.
  ScoreComponent _repaymentComponent(List<LedgerTransaction> txs) {
    final creditByCustomer = <int, double>{};
    final paidByCustomer = <int, double>{};

    for (final tx in txs) {
      final bucket = tx.direction == TxDirection.credit
          ? creditByCustomer
          : paidByCustomer;
      bucket[tx.customerId] = (bucket[tx.customerId] ?? 0) + tx.amount;
    }

    // Only customers who were actually extended credit can demonstrate
    // repayment; a payment-only customer would otherwise inflate the average.
    final scored = creditByCustomer.entries
        .where((e) => e.value > 0)
        .map((e) => ((paidByCustomer[e.key] ?? 0) / e.value).clamp(0.0, 1.0))
        .toList();

    if (scored.isEmpty) {
      return ScoreComponent(
        key: 'repayment',
        label: 'Repayment consistency',
        earned: 0,
        maxPoints: config.repaymentMax,
        explanation: 'No udhar recorded yet, so there is nothing to repay.',
      );
    }

    final avg = scored.reduce((a, b) => a + b) / scored.length;
    final pct = (avg * 100).round();

    return ScoreComponent(
      key: 'repayment',
      label: 'Repayment consistency',
      earned: avg * config.repaymentMax,
      maxPoints: config.repaymentMax,
      explanation: 'On average $pct% of the udhar you give is paid back, '
          'across ${scored.length} ${scored.length == 1 ? 'customer' : 'customers'}.',
    );
  }

  ScoreComponent _tenureComponent(List<LedgerTransaction> txs) {
    if (txs.isEmpty) {
      return ScoreComponent(
        key: 'tenure',
        label: 'Ledger history',
        earned: 0,
        maxPoints: config.tenureMax,
        explanation: 'No entries recorded yet.',
      );
    }

    var earliest = txs.first.createdAt;
    var latest = txs.first.createdAt;
    for (final tx in txs) {
      if (tx.createdAt.isBefore(earliest)) earliest = tx.createdAt;
      if (tx.createdAt.isAfter(latest)) latest = tx.createdAt;
    }

    final days = latest.difference(earliest).inDays;
    final ratio = (days / config.tenureTargetDays).clamp(0.0, 1.0);

    return ScoreComponent(
      key: 'tenure',
      label: 'Ledger history',
      earned: ratio * config.tenureMax,
      maxPoints: config.tenureMax,
      explanation: days <= 0
          ? 'Your ledger starts today. Full marks at '
              '${config.tenureTargetDays} days of history.'
          : '$days days of recorded history '
              '(${config.tenureTargetDays} days earns full marks).',
    );
  }

  ScoreComponent _customerComponent(List<LedgerTransaction> txs) {
    final active = txs.map((t) => t.customerId).toSet().length;
    final ratio = (active / config.customerTarget).clamp(0.0, 1.0);

    return ScoreComponent(
      key: 'customers',
      label: 'Active customers',
      earned: ratio * config.customersMax,
      maxPoints: config.customersMax,
      explanation: active == 0
          ? 'No customers recorded yet.'
          : '$active regular ${active == 1 ? 'customer' : 'customers'} in your '
              'khata (${config.customerTarget} earns full marks).',
    );
  }

  ScoreComponent _velocityComponent(List<LedgerTransaction> txs) {
    final cutoff = _now.subtract(Duration(days: config.velocityWindowDays));
    final recent = txs.where((t) => t.createdAt.isAfter(cutoff)).length;
    final ratio = (recent / config.velocityTargetTx).clamp(0.0, 1.0);

    return ScoreComponent(
      key: 'velocity',
      label: 'Recent activity',
      earned: ratio * config.velocityMax,
      maxPoints: config.velocityMax,
      explanation: recent == 0
          ? 'No entries in the last ${config.velocityWindowDays} days.'
          : '$recent ${recent == 1 ? 'entry' : 'entries'} in the last '
              '${config.velocityWindowDays} days '
              '(${config.velocityTargetTx} earns full marks).',
    );
  }

  // --- Summary stats for the passport --------------------------------------

  LedgerStats statsFor(List<LedgerTransaction> txs) {
    var credit = 0.0;
    var paid = 0.0;
    var voiceCount = 0;
    var scanCount = 0;
    DateTime? earliest;

    for (final tx in txs) {
      if (tx.direction == TxDirection.credit) {
        credit += tx.amount;
      } else {
        paid += tx.amount;
      }
      if (tx.source == TxSource.voice) voiceCount++;
      if (tx.source == TxSource.cameraScan) scanCount++;
      if (earliest == null || tx.createdAt.isBefore(earliest)) {
        earliest = tx.createdAt;
      }
    }

    return LedgerStats(
      transactionCount: txs.length,
      customerCount: txs.map((t) => t.customerId).toSet().length,
      totalCreditExtended: credit,
      totalRepaid: paid,
      outstanding: credit - paid,
      voiceCapturedCount: voiceCount,
      scanCapturedCount: scanCount,
      ledgerStart: earliest,
      historyDays: earliest == null
          ? 0
          : math.max(0, _now.difference(earliest).inDays),
    );
  }
}

/// Headline numbers shown on the passport alongside the score.
class LedgerStats {
  final int transactionCount;
  final int customerCount;
  final double totalCreditExtended;
  final double totalRepaid;
  final double outstanding;
  final int voiceCapturedCount;
  final int scanCapturedCount;
  final DateTime? ledgerStart;
  final int historyDays;

  const LedgerStats({
    required this.transactionCount,
    required this.customerCount,
    required this.totalCreditExtended,
    required this.totalRepaid,
    required this.outstanding,
    required this.voiceCapturedCount,
    required this.scanCapturedCount,
    required this.ledgerStart,
    required this.historyDays,
  });

  double get repaymentRate =>
      totalCreditExtended <= 0 ? 0 : (totalRepaid / totalCreditExtended);
}
