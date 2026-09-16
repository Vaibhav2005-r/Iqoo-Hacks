import '../../models/ledger_transaction.dart';
import '../extraction/amount_parser.dart';
import '../extraction/transaction_draft.dart';
import 'transaction_extractor.dart';

/// Postpositions that can follow a person's name.
///
/// Top-level rather than a class member because both the extractor and the
/// tokeniser need them.
const _namePostpositions = {
  'ko', 'ne', 'ka', 'ki', 'ke', 'se',
  'को', 'ने', 'का', 'की', 'के', 'से',
};

const _honorifics = {
  'ji', 'jee', 'bhai', 'bhaiya', 'behen', 'didi', 'sahab', 'saheb',
  'shri', 'smt', 'mr', 'mrs', 'ms', 'uncle', 'aunty',
  'जी', 'भाई', 'भैया', 'बहन', 'दीदी', 'साहब', 'श्री',
};

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

  @override
  Future<void> dispose() async {}

  /// Words that unambiguously mean the customer paid money back.
  static const _paymentMarkers = {
    'wapas', 'wapis', 'vapas', 'vapis', 'chukaya', 'chukaye', 'chukta',
    'jama', 'bhugtan', 'laut', 'lauta', 'lautaye',
    // Spellings seen coming out of whisper-tiny on Hindi.
    'vaapas', 'waapas', 'vapaas', 'chukai', 'chukaai', 'jamaa',
    'वापस', 'वापिस', 'चुकाया', 'चुकाये', 'जमा', 'भुगतान', 'लौटा', 'लौटाए',
    'paid', 'pay', 'payment', 'repaid', 'repay', 'settled', 'settle',
    'cleared', 'clear', 'returned', 'return',
  };

  /// Words that unambiguously mean the shopkeeper extended credit.
  ///
  /// Only words that carry the meaning on their own. "diya" (gave) is NOT
  /// here: whether giving means credit or repayment depends on who did the
  /// giving, which is what the postposition tells us.
  static const _creditMarkers = {
    'udhar', 'udhaar', 'udhari', 'उधार', 'उधारी',
    'khata', 'खाता', 'likh', 'लिख',
    'credit', 'lend', 'lent', 'borrowed', 'owes',
  };

  /// Verbs of giving — direction depends on who the giver is.
  static const _giveVerbs = {
    'diya', 'diye', 'di', 'de', 'dena', 'diyaa',
    'दिया', 'दिये', 'दिए', 'दी', 'देना',
    'gave', 'give', 'given',
  };

  /// Verbs of taking — direction likewise depends on the actor.
  static const _takeVerbs = {
    'liya', 'liye', 'le', 'lena', 'lia',
    'लिया', 'लिये', 'लिए', 'ले', 'लेना',
    'took', 'take', 'taken',
  };

  /// Ergative marker. Marks the NAMED PERSON as the one who acted:
  /// "Ramesh **ne** ... diye" = Ramesh did the giving = a repayment.
  static const _subjectMarkers = {'ne', 'neh', 'ने'};

  /// Dative marker. Marks the named person as the RECIPIENT:
  /// "Sharma **ko** ... diya" = the shopkeeper gave to Sharma = credit.
  static const _dativeMarkers = {'ko', 'को'};

  /// Everyday Hindi, Hinglish and English words that are never a customer
  /// name.
  ///
  /// This list is what makes lowercase and Devanagari names findable at all.
  /// Capitalisation cannot be relied on — Devanagari has no case, and speech
  /// transcripts are frequently all lower case — so instead of looking for
  /// something that looks like a name, we rule out everything that cannot be
  /// one and take what is left.
  static const _stopwords = {
    // Hindi function words, romanised
    'ka', 'ke', 'ki', 'ko', 'ne', 'se', 'me', 'mein', 'par', 'pe',
    'aur', 'ya', 'bhi', 'hi', 'to', 'hai', 'hain', 'tha', 'the', 'thi',
    'kiya', 'kiye', 'kar', 'karke', 'karna', 'wala', 'wali', 'vaste',
    'aaj', 'kal', 'parso', 'abhi', 'phir', 'ab', 'tab', 'jab', 'tak',
    'sab', 'nahi', 'nahin', 'na', 'haan', 'yeh', 'ye', 'woh', 'wo',
    'is', 'us', 'in', 'un', 'iska', 'uska', 'mera', 'tera', 'hamara',
    'apna', 'baaki', 'baki', 'bacha', 'bache', 'kitna', 'kitne', 'kuch',
    'sara', 'saare', 'total', 'kul',
    // Hindi function words, Devanagari
    'का', 'के', 'की', 'को', 'ने', 'से', 'में', 'पर', 'और', 'या', 'भी',
    'ही', 'है', 'हैं', 'था', 'थे', 'थी', 'किया', 'किए', 'किये', 'कर',
    'करके', 'वाला', 'वाली', 'आज', 'कल', 'अभी', 'फिर', 'अब', 'तब', 'जब',
    'तक', 'सब', 'नहीं', 'ना', 'हाँ', 'यह', 'ये', 'वह', 'वो', 'इस', 'उस',
    'मेरा', 'अपना', 'बाकी', 'कुछ', 'कुल',
    // English function words
    // NOTE: 'to', 'the', 'is' and 'in' are deliberately absent - they are
    // already above as romanised Hindi ("the" = थे, "is" = इस).
    'i', 'you', 'he', 'she', 'we', 'they', 'a', 'an', 'of',
    'for', 'from', 'and', 'or', 'on', 'at', 'are', 'was',
    'were', 'have', 'has', 'had', 'back', 'money', 'cash', 'today',
    'yesterday', 'remaining', 'balance', 'received', 'worth', 'some',
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

      // Test the REPAIRED line. Checking the raw one drops every row whose
      // amount OCR mangled ("5oo"), which is the worst possible failure here:
      // a debt silently missing from the page rather than flagged for review.
      final probe = source == TxSource.cameraScan
          ? AmountParser.repairOcrDigits(line)
          : line;
      if (AmountParser.parse(probe) == null) continue;

      final draft = _extractLine(line, knownCustomers, source);
      // A row with an amount but no recoverable name is still worth showing —
      // the shopkeeper can name it in one tap, which beats silently dropping
      // a real debt off the page.
      drafts.add(draft);
    }
    return drafts;
  }

  TransactionDraft _extractLine(
    String rawText,
    List<String> knownCustomers,
    TxSource source,
  ) {
    final warnings = <String>[];

    // Handwriting OCR reliably confuses o/0 and l/1, so "5oo" arrives where
    // "500" was written. Repair only on the scan path — speech never produces
    // that failure, and the repair should not run where it cannot help.
    final text = source == TxSource.cameraScan
        ? AmountParser.repairOcrDigits(rawText)
        : rawText;

    // One tokenisation shared by name and direction, so their indices line up.
    final tokens = _Tokens.of(text);

    final amount = AmountParser.parse(text);
    if (amount == null) warnings.add('No amount detected');

    final nameResult = _extractName(tokens, knownCustomers);
    if (nameResult.name == null) warnings.add('No customer name detected');

    final direction = _detectDirection(tokens, nameResult.index);
    if (direction.ambiguous) {
      warnings.add('Unclear whether this was udhar given or a payment received');
    }

    final item = _extractItem(tokens);

    final confidence = _scoreConfidence(
      hasAmount: amount != null,
      nameSource: nameResult.matchType,
      directionExplicit: !direction.ambiguous,
    );

    return TransactionDraft(
      customerName: nameResult.name,
      amount: amount,
      item: item,
      direction: direction.value,
      source: source,
      // The ORIGINAL text, not the repaired one: "From the page" should show
      // what the phone actually read, so a repair is visible rather than
      // hidden.
      rawInput: rawText.trim(),
      confidence: confidence,
      warnings: warnings,
    );
  }

  // --- Direction ----------------------------------------------------------

  /// Works out whether this was udhar given or a payment received.
  ///
  /// The crucial signal is the postposition attached to the customer's name,
  /// not the verb. Hindi marks who did what:
  ///
  ///   "Sharma **ko** paanch sau diya"  - Sharma is the RECIPIENT -> CREDIT
  ///   "Ramesh **ne** aath sau diye"    - Ramesh is the ACTOR     -> PAYMENT
  ///
  /// Both sentences use the same verb. Reading the verb alone gets the second
  /// one exactly backwards, which is the bug this replaced: a repayment
  /// recorded as fresh credit, doubling the debt instead of clearing it.
  static _Direction _detectDirection(_Tokens tokens, int? nameIndex) {
    final lower = tokens.lower.toSet();

    // 1. Unambiguous words win outright.
    if (lower.any(_paymentMarkers.contains)) {
      return const _Direction(TxDirection.payment, ambiguous: false);
    }
    if (lower.any(_creditMarkers.contains)) {
      return const _Direction(TxDirection.credit, ambiguous: false);
    }

    final hasGive = lower.any(_giveVerbs.contains);
    final hasTake = lower.any(_takeVerbs.contains);

    // 2. Grammar: the postposition right after the name.
    final marker = nameIndex == null ? null : tokens.postpositionAfter(nameIndex);
    if (marker != null && _subjectMarkers.contains(marker)) {
      // The customer acted.
      if (hasGive) return const _Direction(TxDirection.payment, ambiguous: false);
      if (hasTake) return const _Direction(TxDirection.credit, ambiguous: false);
      // "Ramesh ne 500" - they did something with 500, but not which.
      return const _Direction(TxDirection.payment, ambiguous: true);
    }
    if (marker != null && _dativeMarkers.contains(marker)) {
      // The customer received.
      return const _Direction(TxDirection.credit, ambiguous: false);
    }

    // 3. No grammatical marker. A bare verb means the shopkeeper acted.
    if (hasGive || hasTake) {
      return const _Direction(TxDirection.credit, ambiguous: false);
    }

    // 4. A khata is mostly udhar, so credit is the safer default - but say
    //    that we guessed, because nothing in the sentence settled it.
    return const _Direction(TxDirection.credit, ambiguous: true);
  }

  // --- Name ----------------------------------------------------------------

  /// Finds the customer by elimination rather than by recognition.
  ///
  /// Looking for something name-shaped does not work here: Devanagari has no
  /// capital letters and speech transcripts are often entirely lower case, so
  /// "sharma 500 udhar" and "शर्मा 500 उधार" both used to come back with no
  /// name at all. Instead every token that CANNOT be a name is ruled out, and
  /// what survives is scored by position.
  _NameMatch _extractName(_Tokens tokens, List<String> knownCustomers) {
    // An existing customer name in the text is the strongest possible signal,
    // and it keeps the ledger from sprouting near-duplicate customers.
    final known = _matchKnownCustomer(tokens, knownCustomers);
    if (known != null) {
      return _NameMatch(known.name, _NameMatchType.knownCustomer, known.index);
    }

    var bestScore = 0;
    int? bestIndex;

    for (var i = 0; i < tokens.length; i++) {
      if (!_isNameLike(tokens.lower[i])) continue;

      var score = 1;

      // A postposition right after a token is the clearest marker that the
      // token was a person.
      if (tokens.postpositionAfter(i) != null) score += 100;

      // Capitalisation still helps when it is there; it just cannot be relied
      // on to be there.
      if (_isCapitalised(tokens.original[i])) score += 40;

      // Names tend to lead the sentence.
      score += (30 - i * 5).clamp(0, 30);

      if (score > bestScore) {
        bestScore = score;
        bestIndex = i;
      }
    }

    if (bestIndex == null) {
      return const _NameMatch(null, _NameMatchType.none, null);
    }

    final type = tokens.postpositionAfter(bestIndex) != null
        ? _NameMatchType.postposition
        : _isCapitalised(tokens.original[bestIndex])
            ? _NameMatchType.capitalisation
            : _NameMatchType.elimination;

    return _NameMatch(
      _titleCase(tokens.original[bestIndex]),
      type,
      bestIndex,
    );
  }

  static ({String name, int index})? _matchKnownCustomer(
    _Tokens tokens,
    List<String> known,
  ) {
    ({String name, int index})? best;
    var bestLength = 0;

    for (final candidate in known) {
      final needle = AmountParser.tokenise(candidate);
      if (needle.isEmpty) continue;
      for (var i = 0; i + needle.length <= tokens.length; i++) {
        var match = true;
        for (var j = 0; j < needle.length; j++) {
          if (tokens.lower[i + j] != needle[j]) {
            match = false;
            break;
          }
        }
        if (match && candidate.length > bestLength) {
          best = (name: candidate, index: i + needle.length - 1);
          bestLength = candidate.length;
        }
      }
    }
    return best;
  }

  static bool _isCapitalised(String token) {
    if (token.isEmpty) return false;
    final first = token[0];
    return first == first.toUpperCase() && first != first.toLowerCase();
  }

  static bool _isNameLike(String lower) {
    if (lower.length < 2) return false;
    if (RegExp(r'\d').hasMatch(lower)) return false;
    if (_stopwords.contains(lower)) return false;
    if (_honorifics.contains(lower)) return false;
    if (_namePostpositions.contains(lower)) return false;
    if (AmountParser.currencyWords.contains(lower)) return false;
    if (_paymentMarkers.contains(lower)) return false;
    if (_creditMarkers.contains(lower)) return false;
    if (_giveVerbs.contains(lower)) return false;
    if (_takeVerbs.contains(lower)) return false;
    if (_englishStopwords.contains(lower)) return false;
    if (_itemWords.containsKey(lower)) return false;
    // A bare number word ("paanch") is not a name.
    if (AmountParser.parse(lower) != null) return false;
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

  static String? _extractItem(_Tokens tokens) {
    for (final token in tokens.lower) {
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

enum _NameMatchType {
  knownCustomer,
  postposition,
  capitalisation,

  /// Found by ruling everything else out — the path that makes lowercase and
  /// Devanagari names work at all.
  elimination,

  none,
}

class _NameMatch {
  final String? name;
  final _NameMatchType matchType;

  /// Token index of the name, so direction detection can read the
  /// postposition attached to it.
  final int? index;

  const _NameMatch(this.name, this.matchType, this.index);
}

/// A direction plus whether the sentence actually settled it.
class _Direction {
  const _Direction(this.value, {required this.ambiguous});

  final TxDirection value;

  /// True when nothing in the sentence decided this and we fell back to a
  /// default. The UI turns this into a visible warning rather than a silent
  /// guess.
  final bool ambiguous;
}

/// One tokenisation, kept in both original and lowered form.
///
/// Name finding needs the original case; direction and marker lookups need it
/// lowered. Tokenising twice risked the two drifting out of index alignment,
/// which matters now that direction depends on where the name sits.
class _Tokens {
  const _Tokens(this.original, this.lower);

  final List<String> original;
  final List<String> lower;

  static _Tokens of(String text) {
    final original = AmountParser.normaliseDigits(text)
        .replaceAll(RegExp(r'[^\w\s.\u0900-\u097F]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    return _Tokens(
      original,
      original.map((t) => t.toLowerCase()).toList(),
    );
  }

  int get length => original.length;

  /// The postposition following [index], skipping any honorifics between.
  ///
  /// "Sharma ji ko" - the marker belongs to Sharma, with "ji" in the way.
  String? postpositionAfter(int index) {
    var j = index + 1;
    while (j < length && _honorifics.contains(lower[j])) {
      j++;
    }
    if (j < length && _namePostpositions.contains(lower[j])) return lower[j];
    return null;
  }
}
