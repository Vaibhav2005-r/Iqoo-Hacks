import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:khatasetu/models/ledger_transaction.dart';
import 'package:khatasetu/models/shop.dart';
import 'package:khatasetu/services/passport_service.dart';
import 'package:khatasetu/services/scoring_service.dart';

/// The QR payload is a contract between two codebases that cannot import each
/// other: this app, and the static lender page in `lender/index.html`.
///
/// Nothing else would catch a rename — the app would keep producing a valid
/// QR and the lender page would quietly render blanks. These tests fail
/// instead. If you change the payload, change lender/index.html in the same
/// commit and bump `v`.
void main() {
  final now = DateTime(2026, 9, 17);
  final scoring = ScoringService(now: now);

  String payloadFor(List<LedgerTransaction> txs) {
    return PassportService.buildQrPayload(
      shop: Shop(
        id: 1,
        name: 'Sharma General Store',
        ownerName: 'Ramesh Sharma',
        location: 'Charminar, Hyderabad',
        createdAt: now,
      ),
      snapshot: scoring.compute(shopId: 1, transactions: txs),
      stats: scoring.statsFor(txs),
    );
  }

  LedgerTransaction tx(int customerId, double amount, TxDirection dir, int daysAgo) {
    return LedgerTransaction(
      customerId: customerId,
      amount: amount,
      direction: dir,
      source: TxSource.voice,
      createdAt: now.subtract(Duration(days: daysAgo)),
    );
  }

  final ledger = [
    tx(1, 1000, TxDirection.credit, 90),
    tx(1, 800, TxDirection.payment, 10),
    tx(2, 500, TxDirection.credit, 60),
    tx(2, 500, TxDirection.payment, 5),
    tx(3, 250, TxDirection.credit, 3),
  ];

  test('top-level keys are exactly what the lender page reads', () {
    final json = jsonDecode(payloadFor(ledger)) as Map<String, dynamic>;
    expect(
      json.keys.toSet(),
      {
        'v', 'shop', 'owner', 'loc', 'score', 'display',
        'tx', 'cust', 'days', 'credit', 'repaid', 'out', 'gen', 'parts',
      },
      reason: 'lender/index.html reads exactly these; update both together',
    );
  });

  test('component keys match the four bars the lender page draws', () {
    final json = jsonDecode(payloadFor(ledger)) as Map<String, dynamic>;
    expect(
      (json['parts'] as Map<String, dynamic>).keys.toSet(),
      {'repayment', 'tenure', 'customers', 'velocity'},
    );
  });

  test('version is 1, which is what the reader accepts', () {
    final json = jsonDecode(payloadFor(ledger)) as Map<String, dynamic>;
    expect(json['v'], 1);
  });

  test('numeric fields are numbers, not formatted strings', () {
    // The lender page does its own ₹ formatting and arithmetic on these.
    final json = jsonDecode(payloadFor(ledger)) as Map<String, dynamic>;
    for (final k in ['score', 'display', 'tx', 'cust', 'days',
                     'credit', 'repaid', 'out']) {
      expect(json[k], isA<num>(), reason: '$k must stay numeric');
    }
  });

  test('the date is plain yyyy-MM-dd', () {
    final json = jsonDecode(payloadFor(ledger)) as Map<String, dynamic>;
    expect(json['gen'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
  });

  test('stays small enough to scan off a cracked phone screen', () {
    // QR density is the real constraint; a bloated payload becomes a code
    // that will not read across a bank counter.
    expect(payloadFor(ledger).length, lessThan(700));
  });

  test('round-trips through the app-side decoder', () {
    final decoded = PassportService.decodeQrPayload(payloadFor(ledger));
    expect(decoded, isNotNull);
    expect(decoded!['shop'], 'Sharma General Store');
  });

  test('a foreign version is refused, matching the reader', () {
    expect(PassportService.decodeQrPayload('{"v":2,"shop":"X"}'), isNull);
    expect(PassportService.decodeQrPayload('not json'), isNull);
  });
}
