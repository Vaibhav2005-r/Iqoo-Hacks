import 'package:flutter_test/flutter_test.dart';
import 'package:khatasetu/models/ledger_transaction.dart';
import 'package:khatasetu/services/extraction/amount_parser.dart';
import 'package:khatasetu/services/llm/rule_based_extractor.dart';

/// Tests against VERBATIM whisper-tiny output, not against tidy invented
/// phrases.
///
/// Nine Hindi sentences were spoken through TTS, transcribed by whisper-tiny
/// with `-l hi`, and the raw strings pasted here. Two things about that output
/// shape everything below: whisper returns **romanised Latin, not Devanagari**
/// even when told the language is Hindi, and it **glues short words together**
/// ("chaar sau" -> "Charso").
void main() {
  const ex = RuleBasedExtractor();

  group('glued number segmentation', () {
    test('splits number words whisper ran together', () {
      expect(AmountParser.segmentGluedNumber('charso'), ['char', 'so']);
      expect(AmountParser.segmentGluedNumber('dosoka'), ['do', 'so', 'ka']);
      expect(AmountParser.parse('Raju Cook Charso Goodyaar'), 400);
      expect(AmountParser.parse('Vikasku Dosoka Samandia'), 200);
      expect(AmountParser.parse('Sharma ji Ko 5-Soka Uddhardiya'), 500);
    });

    test('leaves ordinary words alone', () {
      // Must not rewrite names that happen to start with a number word.
      // "Sonu" tries "so" then fails on "nu"; partial matches are rejected.
      expect(AmountParser.segmentGluedNumber('sonu'), isNull);
      expect(AmountParser.segmentGluedNumber('charu'), isNull);
      expect(AmountParser.segmentGluedNumber('sharma'), isNull);
      expect(AmountParser.segmentGluedNumber('ekta'), isNull);
    });

    test('a bare number is left alone', () {
      expect(AmountParser.segmentGluedNumber('500'), isNull);
    });
  });

  group('names survive whisper mangling', () {
    const cases = {
      'Sharma ji Ko 5-Soka Uddhardiya': 'Sharma',
      'Ramesh Netin Subhapaski': 'Ramesh',
      'Priya Kudu 25th ka chavaldia': 'Priya',
      'Sunita Ne 5-10 rupee Jama K.': 'Sunita',
      'Mina ni satsu vaapas di': 'Mina',
      'Raju Cook Charso Goodyaar': 'Raju',
      'Kavita Neh Hazar Rupai Chukai': 'Kavita',
    };

    for (final e in cases.entries) {
      test('"${e.key}" -> ${e.value}', () async {
        final d = await ex.extractSingle(e.key, source: TxSource.voice);
        expect(d.customerName, e.value);
      });
    }

    test('a currency word is never picked as the name', () async {
      // "rupe" used to win over "Anilku" because a postposition followed it.
      final d = await ex.extractSingle('Anilku hasa rupe ka udhardia');
      expect(d.customerName, isNot('Rupe'));
    });
  });

  group('direction survives whisper mangling', () {
    const payments = [
      'Sunita Ne 5-10 rupee Jama K.',
      'Mina ni satsu vaapas di',
      'Kavita Neh Hazar Rupai Chukai',
    ];
    const credits = [
      'Sharma ji Ko 5-Soka Uddhardiya',
      'Priya Kudu 25th ka chavaldia',
      'Raju Cook Charso Goodyaar',
      'Vikasku Dosoka Samandia',
    ];

    for (final t in payments) {
      test('payment: "$t"', () async {
        final d = await ex.extractSingle(t, source: TxSource.voice);
        expect(d.direction, TxDirection.payment);
      });
    }
    for (final t in credits) {
      test('credit: "$t"', () async {
        final d = await ex.extractSingle(t, source: TxSource.voice);
        expect(d.direction, TxDirection.credit);
      });
    }
  });

  group('known limits, recorded deliberately', () {
    test('a name glued to its postposition keeps the suffix', () async {
      // "Vikasku" is "Vikas" + "ko". Stripping ku/ko would break real names
      // like Tinku and Pinku, so this is left for the shopkeeper to correct
      // rather than guessed at.
      final d = await ex.extractSingle('Vikasku Dosoka Samandia');
      expect(d.customerName, 'Vikasku');
    });

    test('a badly mangled amount yields nothing rather than a wrong number',
        () async {
      // whisper heard "paanch sau" as "5-10" and "do sau pachas" as "25th".
      // Neither is recoverable; the draft must arrive incomplete so the
      // confirmation card asks, instead of saving a confident wrong figure.
      final d = await ex.extractSingle('Priya Kudu 25th ka chavaldia');
      expect(d.amount, isNull);
      expect(d.isComplete, isFalse);
    });
  });
}
