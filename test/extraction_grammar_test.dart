import 'package:flutter_test/flutter_test.dart';
import 'package:khatasetu/models/ledger_transaction.dart';
import 'package:khatasetu/services/extraction/transaction_draft.dart';
import 'package:khatasetu/services/llm/rule_based_extractor.dart';

/// Regression tests for the two failures reported from a real phone: names
/// not being found, and the intent of the sentence being read backwards.
void main() {
  const ex = RuleBasedExtractor();

  group('the postposition decides the direction, not the verb', () {
    test('"ko" means the customer received - credit', () async {
      final d = await ex.extractSingle('sharma ko 500 diya');
      expect(d.direction, TxDirection.credit);
    });

    test('"ne" plus a give-verb means the customer paid - payment', () async {
      // The reported bug: identical verb to the case above, opposite meaning.
      // Reading the verb alone recorded a repayment as fresh credit.
      final d = await ex.extractSingle('ramesh ne aath sau diye');
      expect(d.direction, TxDirection.payment);
      expect(d.amount, 800);
      expect(d.customerName, 'Ramesh');
    });

    test('same, in Devanagari', () async {
      final d = await ex.extractSingle('रमेश ने पांच सौ दिए');
      expect(d.direction, TxDirection.payment);
      expect(d.amount, 500);
    });

    test('"ne" plus a take-verb means the customer took goods - credit', () async {
      final d = await ex.extractSingle('ramesh ne udhar liya 800');
      expect(d.direction, TxDirection.credit);
    });

    test('an explicit word still outranks the grammar', () async {
      // "wapas" settles it regardless of how the sentence is built.
      final d = await ex.extractSingle('sharma ko teen sau wapas kiye');
      expect(d.direction, TxDirection.payment);
    });

    test('"ne" with no verb is flagged rather than silently guessed', () async {
      final d = await ex.extractSingle('ramesh ne 500');
      expect(d.confidence, isNot(DraftConfidence.high));
      expect(
        d.warnings,
        contains('Unclear whether this was udhar given or a payment received'),
      );
    });
  });

  group('names are found without capitals or postpositions', () {
    test('lowercase romanised, no postposition', () async {
      // Speech transcripts are frequently all lower case.
      final d = await ex.extractSingle('sharma 500 udhar');
      expect(d.customerName, 'Sharma');
      expect(d.amount, 500);
    });

    test('Devanagari, no postposition', () async {
      // Devanagari has no capital letters at all, so capitalisation-based
      // detection could never have worked here.
      final d = await ex.extractSingle('शर्मा 500 उधार');
      expect(d.customerName, 'शर्मा');
    });

    test('lowercase English sentence', () async {
      final d = await ex.extractSingle('i gave sharma 500 rupees');
      expect(d.customerName, 'Sharma');
    });

    test('a leading time word is not mistaken for the name', () async {
      final d = await ex.extractSingle('aaj sharma ko 200 ka saman diya');
      expect(d.customerName, 'Sharma');
    });

    test('a verb is never taken as the name', () async {
      final d = await ex.extractSingle('kal ramesh ne 400 jama kiye');
      expect(d.customerName, 'Ramesh');
      expect(d.direction, TxDirection.payment);
    });

    test('an item word is not taken as the name', () async {
      final d = await ex.extractSingle('priya ko 250 ka chawal diya');
      expect(d.customerName, 'Priya');
      expect(d.item, 'Rice');
    });

    test('still refuses to invent a name when there is none', () async {
      final d = await ex.extractSingle('500 ka udhar diya');
      expect(d.customerName, isNull);
    });

    test('an honorific between name and postposition is skipped', () async {
      final d = await ex.extractSingle('anil bhai ko 1200 udhar');
      expect(d.customerName, 'Anil');
    });
  });
}
