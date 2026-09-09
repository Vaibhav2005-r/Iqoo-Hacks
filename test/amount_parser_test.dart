import 'package:flutter_test/flutter_test.dart';
import 'package:khatasetu/services/extraction/amount_parser.dart';

void main() {
  group('digits', () {
    test('plain number', () {
      expect(AmountParser.parse('500'), 500);
      expect(AmountParser.parse('1500.50'), 1500.50);
    });

    test('Indian digit grouping is stripped, not split into two numbers', () {
      expect(AmountParser.parse('1,500 rupaye'), 1500);
      expect(AmountParser.parse('1,23,456'), 123456);
    });

    test('Devanagari digits', () {
      expect(AmountParser.parse('५००'), 500);
    });

    test('digit with a Hindi multiplier', () {
      expect(AmountParser.parse('5 sau'), 500);
      expect(AmountParser.parse('2 hazaar'), 2000);
    });

    test('a quantity does not win over the amount', () {
      // "2 kilo of rice, 500 rupees" — the amount is the one next to rupaye.
      expect(AmountParser.parse('2 kilo chawal 500 rupaye'), 500);
    });

    test('currency adjacency beats size', () {
      // 50 sits next to "rupaye"; 2000 is a bag weight in grams.
      expect(AmountParser.parse('2000 gram atta 50 rupaye'), 50);
    });
  });

  group('mixed digit and word numbers', () {
    test('a word amount next to rupaye beats a stray digit quantity', () {
      // The naive "digits always win" rule reads this as 2.
      expect(
        AmountParser.parse('paanch sau rupaye ka 2 kilo chawal'),
        500,
      );
    });

    test('a digit amount next to rupaye beats a larger word quantity', () {
      // ...and the reverse: 300 here is a weight in grams, 20 is the price.
      expect(AmountParser.parse('20 rupaye ka teen sau gram'), 20);
    });

    test('with no currency word, the larger number wins', () {
      expect(AmountParser.parse('paanch kilo chawal teen sau'), 300);
    });
  });

  group('Hindi word numbers', () {
    test('romanised', () {
      expect(AmountParser.parse('paanch sau'), 500);
      expect(AmountParser.parse('do hazaar'), 2000);
      expect(AmountParser.parse('do hazaar paanch sau'), 2500);
      expect(AmountParser.parse('teen sau'), 300);
    });

    test('Devanagari, as whisper actually transcribes Hindi', () {
      expect(AmountParser.parse('पांच सौ'), 500);
      expect(AmountParser.parse('दो हजार'), 2000);
    });

    test('colloquial fractions', () {
      expect(AmountParser.parse('dhai sau'), 250);
      expect(AmountParser.parse('derh sau'), 150);
      expect(AmountParser.parse('sava sau'), 125);
      expect(AmountParser.parse('saade teen sau'), 350);
    });

    test('separate numbers are not accumulated together', () {
      // Two distinct runs: a 5 kg quantity and a 300 rupee amount. Summing
      // them would give 800, which is the bug this guards.
      expect(AmountParser.parse('paanch kilo chawal teen sau'), 300);
    });

    test('a full sentence', () {
      expect(
        AmountParser.parse('Sharma ji ko paanch sau ka udhar diya'),
        500,
      );
    });
  });

  group('no amount present', () {
    test('returns null rather than zero', () {
      expect(AmountParser.parse('Sharma ji ko udhar diya'), isNull);
      expect(AmountParser.parse(''), isNull);
      expect(AmountParser.parse('   '), isNull);
    });
  });

  group('tokenise', () {
    test('keeps Devanagari, drops punctuation', () {
      expect(
        AmountParser.tokenise('Sharma ji, ₹500 ka udhar!'),
        ['sharma', 'ji', '500', 'ka', 'udhar'],
      );
      expect(AmountParser.tokenise('पांच सौ'), ['पांच', 'सौ']);
    });
  });
}
