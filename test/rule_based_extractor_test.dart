import 'package:flutter_test/flutter_test.dart';
import 'package:khatasetu/models/ledger_transaction.dart';
import 'package:khatasetu/services/extraction/transaction_draft.dart';
import 'package:khatasetu/services/llm/rule_based_extractor.dart';

void main() {
  const extractor = RuleBasedExtractor();

  group('direction', () {
    test('udhar phrasing is credit', () async {
      final d = await extractor.extractSingle(
        'Sharma ji ko paanch sau ka udhar diya',
      );
      expect(d.direction, TxDirection.credit);
    });

    test('wapas phrasing is a payment', () async {
      final d = await extractor.extractSingle('Ramesh ne teen sau wapas kiye');
      expect(d.direction, TxDirection.payment);
    });

    test('English payment wording', () async {
      final d = await extractor.extractSingle('Priya paid 200');
      expect(d.direction, TxDirection.payment);
    });

    test('a payment marker outranks an ambiguous credit marker', () async {
      // "diye" reads as credit on its own, but "wapas" makes this a repayment.
      final d = await extractor.extractSingle('Ramesh ne paise wapas diye 500');
      expect(d.direction, TxDirection.payment);
    });

    test('defaults to credit when nothing is explicit', () async {
      final d = await extractor.extractSingle('Sharma 500');
      expect(d.direction, TxDirection.credit);
    });
  });

  group('customer name', () {
    test('name before a Hindi postposition, honorific stripped', () async {
      final d = await extractor.extractSingle(
        'Sharma ji ko paanch sau ka udhar diya',
      );
      expect(d.customerName, 'Sharma');
    });

    test('name before "ne"', () async {
      final d = await extractor.extractSingle('Ramesh ne teen sau wapas kiye');
      expect(d.customerName, 'Ramesh');
    });

    test('capitalised English name', () async {
      final d = await extractor.extractSingle('Priya paid 200');
      expect(d.customerName, 'Priya');
    });

    test('an existing customer keeps its stored spelling', () async {
      final d = await extractor.extractSingle(
        'sharma ji ko 500 diya',
        knownCustomers: ['Sharma'],
      );
      expect(d.customerName, 'Sharma');
    });

    test('never invents a name when none was said', () async {
      final d = await extractor.extractSingle('500 ka udhar diya');
      expect(d.customerName, isNull);
      expect(d.warnings, contains('No customer name detected'));
      expect(d.isComplete, isFalse);
      expect(d.missingFields, contains('customer name'));
    });

    test('a number word is not mistaken for a name', () async {
      final d = await extractor.extractSingle('paanch sau ka udhar diya');
      expect(d.customerName, isNull);
    });
  });

  group('Devanagari, the script whisper actually emits for Hindi', () {
    test('name, amount and direction from a full Devanagari sentence', () async {
      final d = await extractor.extractSingle('शर्मा जी को पांच सौ का उधार दिया');
      expect(d.customerName, 'शर्मा');
      expect(d.amount, 500);
      expect(d.direction, TxDirection.credit);
    });

    test('Devanagari payment wording', () async {
      final d = await extractor.extractSingle('रमेश ने तीन सौ वापस किए');
      expect(d.amount, 300);
      expect(d.direction, TxDirection.payment);
    });
  });

  group('amount and item', () {
    test('amount is extracted alongside the name', () async {
      final d = await extractor.extractSingle(
        'Sharma ji ko paanch sau ka udhar diya',
      );
      expect(d.amount, 500);
    });

    test('known kirana goods surface as the item', () async {
      final d = await extractor.extractSingle(
        'Sharma ji ko 500 ka chawal diya',
      );
      expect(d.item, 'Rice');
    });

    test('a missing amount is flagged, not defaulted to zero', () async {
      final d = await extractor.extractSingle('Sharma ji ko udhar diya');
      expect(d.amount, isNull);
      expect(d.isComplete, isFalse);
    });
  });

  group('confidence', () {
    test('known customer plus explicit direction is high', () async {
      final d = await extractor.extractSingle(
        'Sharma ji ko 500 ka udhar diya',
        knownCustomers: ['Sharma'],
      );
      expect(d.confidence, DraftConfidence.high);
    });

    test('anything missing is low', () async {
      final d = await extractor.extractSingle('500 diya');
      expect(d.confidence, DraftConfidence.low);
    });
  });

  group('batch extraction from an OCR page', () {
    test('one draft per line that carries an amount', () async {
      final drafts = await extractor.extractBatch(
        'Sharma ji 500 udhar\n'
        'Ramesh 300 wapas\n'
        'Total\n'
        'Priya 250 udhar',
      );
      expect(drafts.length, 3);
      expect(drafts[0].customerName, 'Sharma');
      expect(drafts[1].direction, TxDirection.payment);
      expect(drafts[2].amount, 250);
    });

    test('rows are marked as scanned', () async {
      final drafts = await extractor.extractBatch('Sharma 500 udhar');
      expect(drafts.single.source, TxSource.cameraScan);
    });

    test('a row with an amount but no name is kept for the user to fix', () async {
      // Dropping it would silently lose a real debt off the page.
      final drafts = await extractor.extractBatch('500 udhar');
      expect(drafts.length, 1);
      expect(drafts.single.customerName, isNull);
      expect(drafts.single.isComplete, isFalse);
    });
  });
}
