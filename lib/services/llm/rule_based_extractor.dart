import '../../models/ledger_transaction.dart';
import '../extraction/amount_parser.dart';
import '../extraction/transaction_draft.dart';
import 'transaction_extractor.dart';

/// Deterministic on-device extractor for khata utterances.
///
/// This is not a placeholder for the LLM — it is the safety net the product
/// design depends on. It runs in microseconds, needs no model file, never
/// hallucinates a customer name, and is what keeps the demo alive if the GGUF
/// model fails to load on stage. When the LLM is available it goes first and
/// this cross-checks it; when the LLM is not, this runs alone.
class RuleBasedExtractor implements TransactionExtractor {
  const RuleBasedExtractor();

  @override
  String get engineName => 'On-device rules';

  @override
  Future<bool> isAvailable() async => true;

  /// Words that signal the customer paid money back.
  static const _paymentMarkers = {
    'wapas', 'wapis', 'vapas', 'vapis', 'chukaya', 'chukaye', 'chukta',
    'jama', 'bhugtan', 'laut', 'lauta', 'lautaye', 'diye wapas',
    'वापस', 'वापिस', 'चुकाया',
    'चुकाये', 'जमा', 'भुगतान',
    'लौटा', 'लौटाए',
    'paid', 'pay', 'payment', 'repaid', 'repay', 'settled', 'settle',
    'cleared', 'clear', 'returned', 'return', 'received',
  };

  /// Words that signal the shopkeeper extended credit.
  static const _creditMarkers = {
    'udhar', 'udhaar', 'udhari', 'उधार', 'उधारी',
    'diya', 'diye', 'de', 'di', 'दिया', 'दिये',
    'दिए', 'दी',
    'liya', 'liye', 'लिया', 'ले',
    'khata', 'खाता', 'likh', 'लिख',
    'credit', 'gave', 'give', 'given', 'took', 'takes', 'owes', 'lend',
    'lent', 'borrowed',
  };

  /// Hindi postpositions that follow a person's name.
  static const _namePostpositions = {
    'ko', 'ne', 'ka', 'ki', 'ke', 'se',
    'को', 'ने', 'का', 'की', 'के', 'से',
  };

  static const _honorifics = {
    'ji', 'jee', 'bhai', 'bhaiya', 'behen', 'didi', 'sahab', 'saheb',
    'shri', 'smt', 'mr', 'mrs', 'ms', 'uncle', 'aunty',
    'जी', 'भाई', 'भैया',
    'बहन', 'दीदी', 'साहब', 'श्री',
  };

  /// English words that are capitalised mid-sentence but are never names.
  static const _englishStopwords = {
    'i', 'gave', 'give', 'given', 'took', 'take', 'paid', 'pay', 'rupees',
    'rupee', 'credit', 'payment', 'today', 'yesterday', 'the', 'a', 'an',
    'of', 'to', 'for', 'from', 'and', 'on', 'in', 'has', 'have', 'back',
    'money', 'cash', 'received', 'returned', 'settled', 'owes', 'worth',
  };

  @override
  Future<TransactionDraft> extractSingle(
    String text, {
    List<String> knownCustomers = const [],
    TxSource source = TxSource.voice,
  }) async {
    return _extractLine(text, knownCustomers, source);
  }

  @override
  Future<List<TransactionDraft>> extractBatch(
    String text, {
    List<String> knownCustomers = const [],
    TxSource source = TxSource.cameraScan,
  }) async {
    // A khata page is line-oriented: one customer/amount per row. Split on
    // newlines and keep any line that carries a number.
    final drafts = <TransactionDraft>[];
    for (final rawLine in text.split(RegExp(r'[\r\n]+'))) {
      final line = rawLine.trim();
      if (line.length < 2) continue;
      if (AmountParser.parse(line) == null) continue;

      final draft = _extractLine(line, knownCustomers, source);
      // A row with an amount but no recoverable name is still worth showing —
      // the shopkeeper can name it in one tap, which beats silently dropping
      // a real debt off the page.
      drafts.add(draft);
    }
    return drafts;
  }

  TransactionDraft _extractLine(
    String text,
    List<String> knownCustomers,
    TxSource source,
  ) {
    final warnings = <String>[];

    final amount = AmountParser.parse(text);
    if (amount == null) warnings.add('No amount detected');

    final direction = _detectDirection(text);
    final nameResult = _extractName(text, knownCustomers);
    if (nameResult.name == null) warnings.add('No customer name detected');

    final item = _extractItem(text);

    final confidence = _scoreConfidence(
      hasAmount: amount != null,
      nameSource: nameResult.matchType,
      directionExplicit: _hasExplicitDirection(text),
    );

    return TransactionDraft(
      customerName: nameResult.name,
      amount: amount,
      item: item,
      direction: direction,
      source: source,
      rawInput: text.trim(),
      confidence: confidence,
      warnings: warnings,
    );
  }

  // --- Direction -----------------------------------------------------------

  /// Payment markers are checked first because they are more specific:
  /// "paise wapas diye" contains both "diye" (credit-ish) and "wapas"
  /// (payment), and the payment reading is the correct one.
  static TxDirection _detectDirection(String text) {
    final tokens = AmountParser.tokenise(text).toSet();
    if (tokens.any(_paymentMarkers.contains)) return TxDirection.payment;
    if (tokens.any(_creditMarkers.contains)) return TxDirection.credit;
    // A khata is mostly udhar; defaulting to credit is the safer guess, and
    // the confirmation card makes it a one-tap fix either way.
    return TxDirection.credit;
  }

  static bool _hasExplicitDirection(String text) {
    final tokens = AmountParser.tokenise(text).toSet();
    return tokens.any(_paymentMarkers.contains) ||
        tokens.any(_creditMarkers.contains);
  }

  // --- Name ----------------------------------------------------------------

  _NameMatch _extractName(String text, List<String> knownCustomers) {
    // 1. An existing customer name appearing in the text is the strongest
    //    possible signal, and it also keeps the ledger from sprouting
    //    near-duplicate customers.
    final known = _matchKnownCustomer(text, knownCustomers);
    if (known != null) return _NameMatch(known, _NameMatchType.knownCustomer);

    // 2. Hindi postposition anchor: the word(s) before ko/ne/ka/ki.
    final anchored = _nameBeforePostposition(text);
    if (anchored != null) {
      return _NameMatch(anchored, _NameMatchType.postposition);
    }

    // 3. English: a capitalised token that isn't a sentence-initial stopword.
    final capitalised = _capitalisedName(text);
    if (capitalised != null) {
      return _NameMatch(capitalised, _NameMatchType.capitalisation);
    }

    return const _NameMatch(null, _NameMatchType.none);
  }

  static String? _matchKnownCustomer(String text, List<String> known) {
    final haystack = ' ${AmountParser.tokenise(text).join(' ')} ';
    String? best;
    var bestLength = 0;
    for (final candidate in known) {
      final needle = AmountParser.tokenise(candidate).join(' ');
      if (needle.isEmpty) continue;
      if (haystack.contains(' $needle ') && needle.length > bestLength) {
        best = candidate;
        bestLength = needle.length;
      }
    }
    return best;
  }

  static String? _nameBeforePostposition(String text) {
    // Work on the original casing so the saved name reads properly.
    final rawTokens = text
        .replaceAll(RegExp(r'[^\w\sऀ-ॿ]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();

    for (var i = 0; i < rawTokens.length; i++) {
      if (!_namePostpositions.contains(rawTokens[i].toLowerCase())) continue;

      // Walk backwards over honorifics to the actual name token.
      var j = i - 1;
      while (j >= 0 && _honorifics.contains(rawTokens[j].toLowerCase())) {
        j--;
      }
      if (j < 0) continue;

      final candidate = rawTokens[j];
      if (_isNameLike(candidate)) return _titleCase(candidate);
    }
    return null;
  }

  static String? _capitalisedName(String text) {
    final rawTokens = text
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();

    for (var i = 0; i < rawTokens.length; i++) {
      final token = rawTokens[i];
      if (token.length < 2) continue;
      final first = token[0];
      if (first != first.toUpperCase() || first == first.toLowerCase()) {
        continue;
      }
      if (_englishStopwords.contains(token.toLowerCase())) continue;
      if (_honorifics.contains(token.toLowerCase())) continue;
      if (RegExp(r'\d').hasMatch(token)) continue;
      // A capitalised word at position 0 is usually just sentence case, so
      // only trust it when nothing else in the sentence is capitalised.
      if (i == 0 && rawTokens.length > 1) {
        final laterCapital = rawTokens.skip(1).any(
              (t) =>
                  t.isNotEmpty &&
                  t[0] == t[0].toUpperCase() &&
                  t[0] != t[0].toLowerCase(),
            );
        if (laterCapital) continue;
      }
      return _titleCase(token);
    }
    return null;
  }

  static bool _isNameLike(String token) {
    if (token.length < 2) return false;
    if (RegExp(r'\d').hasMatch(token)) return false;
    final lower = token.toLowerCase();
    if (_englishStopwords.contains(lower)) return false;
    if (_honorifics.contains(lower)) return false;
    if (AmountParser.currencyWords.contains(lower)) return false;
    if (_paymentMarkers.contains(lower)) return false;
    if (_creditMarkers.contains(lower)) return false;
    if (AmountParser.tokenise(token).isEmpty) return false;
    // A bare number word ("paanch") is not a name.
    if (AmountParser.parse(token) != null) return false;
    return true;
  }

  static String _titleCase(String token) {
    if (token.isEmpty) return token;
    // Devanagari has no case; leave it untouched.
    if (token[0].toUpperCase() == token[0].toLowerCase()) return token;
    return token[0].toUpperCase() + token.substring(1).toLowerCase();
  }

  // --- Item ----------------------------------------------------------------

  /// Common kirana goods, so "5 kilo chawal" surfaces "chawal" as the item.
  static const _itemWords = {
    'chawal': 'Rice', 'rice': 'Rice', 'चावल': 'Rice',
    'atta': 'Flour', 'aata': 'Flour', 'flour': 'Flour', 'आटा': 'Flour',
    'dal': 'Dal', 'daal': 'Dal', 'दाल': 'Dal',
    'tel': 'Oil', 'oil': 'Oil', 'तेल': 'Oil',
    'cheeni': 'Sugar', 'chini': 'Sugar', 'sugar': 'Sugar',
    'चीनी': 'Sugar',
    'namak': 'Salt', 'salt': 'Salt', 'नमक': 'Salt',
    'doodh': 'Milk', 'dudh': 'Milk', 'milk': 'Milk',
    'दूध': 'Milk',
    'sabzi': 'Vegetables', 'sabji': 'Vegetables',
    'सब्जी': 'Vegetables',
    'masala': 'Spices', 'मसाला': 'Spices',
    'biscuit': 'Biscuits', 'chai': 'Tea', 'tea': 'Tea',
    'चाय': 'Tea',
    'saman': 'Goods', 'samaan': 'Goods', 'सामान': 'Goods',
  };

  static String? _extractItem(String text) {
    final tokens = AmountParser.tokenise(text);
    for (final token in tokens) {
      final item = _itemWords[token];
      if (item != null) return item;
    }
    return null;
  }

  // --- Confidence ----------------------------------------------------------

  static DraftConfidence _scoreConfidence({
    required bool hasAmount,
    required _NameMatchType nameSource,
    required bool directionExplicit,
  }) {
    if (!hasAmount || nameSource == _NameMatchType.none) {
      return DraftConfidence.low;
    }
    if (nameSource == _NameMatchType.knownCustomer && directionExplicit) {
      return DraftConfidence.high;
    }
    return DraftConfidence.medium;
  }
}

enum _NameMatchType { knownCustomer, postposition, capitalisation, none }

class _NameMatch {
  final String? name;
  final _NameMatchType matchType;
  const _NameMatch(this.name, this.matchType);
}
