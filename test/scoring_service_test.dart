import 'package:flutter_test/flutter_test.dart';
import 'package:khatasetu/models/ledger_transaction.dart';
import 'package:khatasetu/models/trust_score.dart';
import 'package:khatasetu/services/scoring_service.dart';

void main() {
  final now = DateTime(2026, 1, 1);
  final scoring = ScoringService(now: now);

  LedgerTransaction tx({
    required int customerId,
    required double amount,
    required TxDirection direction,
    required int daysAgo,
  }) {
    return LedgerTransaction(
      customerId: customerId,
      amount: amount,
      direction: direction,
      source: TxSource.voice,
      createdAt: now.subtract(Duration(days: daysAgo)),
    );
  }

  double earned(TrustScoreSnapshot s, String key) =>
      s.components.firstWhere((c) => c.key == key).earned;

  group('empty ledger', () {
    test('scores zero without dividing by zero', () {
      final s = scoring.compute(shopId: 1, transactions: []);
      expect(s.score, 0);
      expect(s.components, hasLength(4));
      for (final c in s.components) {
        expect(c.earned, 0);
      }
    });

    test('is provisional', () {
      expect(scoring.isProvisional([]), isTrue);
    });
  });

  group('repayment consistency', () {
    test('averages the per-customer repayment ratio', () {
      final s = scoring.compute(
        shopId: 1,
        transactions: [
          // Fully repaid.
          tx(customerId: 1, amount: 1000, direction: TxDirection.credit, daysAgo: 60),
          tx(customerId: 1, amount: 1000, direction: TxDirection.payment, daysAgo: 10),
          // Half repaid.
          tx(customerId: 2, amount: 1000, direction: TxDirection.credit, daysAgo: 60),
          tx(customerId: 2, amount: 500, direction: TxDirection.payment, daysAgo: 10),
        ],
      );
      // (1.0 + 0.5) / 2 = 0.75 of 40 points.
      expect(earned(s, 'repayment'), closeTo(30.0, 0.001));
    });

    test('is weighted by money, not by transaction count', () {
      // A single token payment against a large debt must not read as
      // "fully repaid" — this is why the component uses amounts.
      final s = scoring.compute(
        shopId: 1,
        transactions: [
          tx(customerId: 1, amount: 5000, direction: TxDirection.credit, daysAgo: 30),
          tx(customerId: 1, amount: 10, direction: TxDirection.payment, daysAgo: 5),
        ],
      );
      expect(earned(s, 'repayment'), lessThan(1.0));
    });

    test('overpayment does not exceed full marks', () {
      final s = scoring.compute(
        shopId: 1,
        transactions: [
          tx(customerId: 1, amount: 100, direction: TxDirection.credit, daysAgo: 30),
          tx(customerId: 1, amount: 900, direction: TxDirection.payment, daysAgo: 5),
        ],
      );
      expect(earned(s, 'repayment'), 40.0);
    });

    test('a payment-only customer does not inflate the average', () {
      final base = [
        tx(customerId: 1, amount: 1000, direction: TxDirection.credit, daysAgo: 60),
        tx(customerId: 1, amount: 500, direction: TxDirection.payment, daysAgo: 10),
      ];
      final withPaymentOnly = [
        ...base,
        tx(customerId: 2, amount: 400, direction: TxDirection.payment, daysAgo: 10),
      ];

      expect(
        earned(scoring.compute(shopId: 1, transactions: withPaymentOnly), 'repayment'),
        earned(scoring.compute(shopId: 1, transactions: base), 'repayment'),
      );
    });

    test('says so plainly when no credit has been extended', () {
      final s = scoring.compute(
        shopId: 1,
        transactions: [
          tx(customerId: 1, amount: 100, direction: TxDirection.payment, daysAgo: 5),
        ],
      );
      final c = s.components.firstWhere((c) => c.key == 'repayment');
      expect(c.earned, 0);
      expect(c.explanation, contains('No udhar'));
    });
  });

  group('other components', () {
    final ledger = [
      tx(customerId: 1, amount: 1000, direction: TxDirection.credit, daysAgo: 60),
      tx(customerId: 1, amount: 1000, direction: TxDirection.payment, daysAgo: 10),
      tx(customerId: 2, amount: 1000, direction: TxDirection.credit, daysAgo: 60),
      tx(customerId: 2, amount: 500, direction: TxDirection.payment, daysAgo: 10),
    ];

    test('tenure measures earliest to latest entry', () {
      final s = scoring.compute(shopId: 1, transactions: ledger);
      // 50 days spanned, out of a 180-day target, over 20 points.
      expect(earned(s, 'tenure'), closeTo(50 / 180 * 20, 0.001));
    });

    test('active customers counts distinct ids', () {
      final s = scoring.compute(shopId: 1, transactions: ledger);
      expect(earned(s, 'customers'), closeTo(2 / 15 * 20, 0.001));
    });

    test('velocity counts only the last 30 days', () {
      final s = scoring.compute(shopId: 1, transactions: ledger);
      // Two entries at 10 days ago; the 60-day-old ones fall outside.
      expect(earned(s, 'velocity'), closeTo(2 / 40 * 20, 0.001));
    });

    test('components never exceed their caps', () {
      final many = [
        for (var i = 0; i < 100; i++)
          tx(customerId: i, amount: 100, direction: TxDirection.credit, daysAgo: 1),
        for (var i = 0; i < 100; i++)
          tx(customerId: i, amount: 100, direction: TxDirection.payment, daysAgo: 1),
        tx(customerId: 1, amount: 10, direction: TxDirection.credit, daysAgo: 5000),
      ];
      final s = scoring.compute(shopId: 1, transactions: many);
      for (final c in s.components) {
        expect(c.earned, lessThanOrEqualTo(c.maxPoints));
      }
      expect(s.score, lessThanOrEqualTo(100));
    });
  });

  group('presentation', () {
    test('display score maps 0-100 onto 300-850', () {
      TrustScoreSnapshot snap(double score) => TrustScoreSnapshot(
            shopId: 1,
            score: score,
            computedAt: now,
            components: const [],
          );

      expect(snap(0).displayScore, 300);
      expect(snap(100).displayScore, 850);
      expect(snap(50).displayScore, 575);
    });

    test('bands follow the score', () {
      TrustScoreSnapshot snap(double score) => TrustScoreSnapshot(
            shopId: 1,
            score: score,
            computedAt: now,
            components: const [],
          );

      expect(snap(10).band, ScoreBand.insufficient);
      expect(snap(30).band, ScoreBand.early);
      expect(snap(60).band, ScoreBand.building);
      expect(snap(80).band, ScoreBand.strong);
    });

    test('components survive a round trip through the snapshot row', () {
      final s = scoring.compute(
        shopId: 7,
        transactions: [
          tx(customerId: 1, amount: 1000, direction: TxDirection.credit, daysAgo: 30),
          tx(customerId: 1, amount: 750, direction: TxDirection.payment, daysAgo: 5),
        ],
      );

      final restored = TrustScoreSnapshot.fromMap({
        ...s.toMap(),
        'id': 1,
      });

      expect(restored.score, s.score);
      expect(restored.shopId, 7);
      expect(restored.components.length, 4);
      expect(
        restored.components.map((c) => c.key),
        s.components.map((c) => c.key),
      );
      expect(
        restored.components.first.explanation,
        s.components.first.explanation,
      );
    });
  });

  group('ledger stats', () {
    test('totals credit, repayment and outstanding', () {
      final stats = scoring.statsFor([
        tx(customerId: 1, amount: 1000, direction: TxDirection.credit, daysAgo: 30),
        tx(customerId: 1, amount: 400, direction: TxDirection.payment, daysAgo: 5),
        tx(customerId: 2, amount: 600, direction: TxDirection.credit, daysAgo: 20),
      ]);

      expect(stats.totalCreditExtended, 1600);
      expect(stats.totalRepaid, 400);
      expect(stats.outstanding, 1200);
      expect(stats.customerCount, 2);
      expect(stats.transactionCount, 3);
      expect(stats.historyDays, 30);
    });

    test('empty ledger has no start date and no history', () {
      final stats = scoring.statsFor([]);
      expect(stats.ledgerStart, isNull);
      expect(stats.historyDays, 0);
      expect(stats.repaymentRate, 0);
    });
  });
}
