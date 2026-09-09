/// Parses rupee amounts out of spoken or OCR'd text, in Hindi (Devanagari and
/// romanised) and English.
///
/// This matters more than it looks: whisper transcribing Hindi emits
/// Devanagari, not romanised Hindi, so "पांच सौ" has to parse as 500 just as
/// reliably as "paanch sau" or "500".
class AmountParser {
  const AmountParser._();

  /// Devanagari digits ० through ९.
  static const _devanagariDigits = {
    '०': '0', '१': '1', '२': '2', '३': '3',
    '४': '4', '५': '5', '६': '6', '७': '7',
    '८': '8', '९': '9',
  };

  /// Units and tens. Romanised spellings are deliberately generous — ASR and
  /// shopkeepers both spell these many ways.
  static const _units = <String, double>{
    // Romanised Hindi
    'ek': 1, 'do': 2, 'teen': 3, 'tin': 3, 'char': 4, 'chaar': 4,
    'panch': 5, 'paanch': 5, 'pach': 5, 'chah': 6, 'chhe': 6, 'che': 6,
    'saat': 7, 'sat': 7, 'aath': 8, 'ath': 8, 'nau': 9, 'no': 9,
    'das': 10, 'dus': 10, 'gyarah': 11, 'barah': 12, 'terah': 13,
    'chaudah': 14, 'pandrah': 15, 'solah': 16, 'satrah': 17,
    'atharah': 18, 'unnis': 19, 'bees': 20, 'bis': 20, 'pachees': 25,
    'pachis': 25, 'tees': 30, 'tis': 30, 'chalees': 40, 'chalis': 40,
    'pachas': 50, 'pachaas': 50, 'saath': 60, 'sattar': 70,
    'assi': 80, 'nabbe': 90,
    // Devanagari
    'एक': 1, 'दो': 2, 'तीन': 3,
    'चार': 4, 'पांच': 5,
    'पाँच': 5, 'छह': 6, 'छे': 6,
    'सात': 7, 'आठ': 8, 'नौ': 9,
    'दस': 10, 'बीस': 20, 'तीस': 30,
    'चालीस': 40, 'पचास': 50,
    'साठ': 60, 'सत्तर': 70,
    'अस्सी': 80, 'नब्बे': 90,
    // English
    'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6,
    'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10, 'eleven': 11,
    'twelve': 12, 'thirteen': 13, 'fourteen': 14, 'fifteen': 15,
    'sixteen': 16, 'seventeen': 17, 'eighteen': 18, 'nineteen': 19,
    'twenty': 20, 'thirty': 30, 'forty': 40, 'fifty': 50, 'sixty': 60,
    'seventy': 70, 'eighty': 80, 'ninety': 90,
  };

  /// Colloquial fractions that act as multiplicands: "dhai sau" = 250.
  static const _fractions = <String, double>{
    'aadha': 0.5, 'adha': 0.5, 'sava': 1.25, 'savaa': 1.25,
    'derh': 1.5, 'dedh': 1.5, 'dhai': 2.5, 'dhaai': 2.5,
    'आधा': 0.5, 'सवा': 1.25,
    'डेढ़': 1.5, 'ढाई': 2.5,
    'half': 0.5,
  };

  static const _multipliers = <String, double>{
    'sau': 100, 'so': 100, 'सौ': 100, 'hundred': 100,
    'hazaar': 1000, 'hazar': 1000, 'hajaar': 1000, 'hajar': 1000,
    'हजार': 1000, 'हज़ार': 1000,
    'thousand': 1000, 'k': 1000,
    'lakh': 100000, 'lac': 100000, 'लाख': 100000,
  };

  /// Words that mean "rupees" and carry no numeric value.
  static const currencyWords = {
    'rupee', 'rupees', 'rupaye', 'rupaya', 'rupay', 'rs', 'inr',
    'रुपये', 'रुपए',
    'रुपया', 'रु',
  };

  /// Normalises Devanagari digits to ASCII and removes digit-grouping commas
  /// so a single regex handles both scripts.
  ///
  /// The comma pass runs in a loop because Indian grouping is irregular
  /// (1,23,456) and one replace pass cannot handle adjacent groups.
  static String normaliseDigits(String input) {
    var out = input;
    _devanagariDigits.forEach((dev, ascii) {
      out = out.replaceAll(dev, ascii);
    });

    final groupComma = RegExp(r'(\d),(\d)');
    while (groupComma.hasMatch(out)) {
      out = out.replaceAllMapped(groupComma, (m) => '${m[1]}${m[2]}');
    }
    return out;
  }

  static List<String> tokenise(String input) {
    return normaliseDigits(input)
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s.ऀ-ॿ]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
  }

  /// Best-effort amount for a whole utterance. Returns null when nothing
  /// number-shaped is present.
  ///
  /// A khata sentence often carries more than one number — a quantity and an
  /// amount — so every candidate is collected from both the digit and word
  /// forms, and one is chosen by two rules:
  ///
  ///   1. a number sitting next to "rupaye"/"rs" is the amount;
  ///   2. failing that, the largest, since quantities are small and amounts
  ///      are not.
  ///
  /// Adjacency has to outrank digits-over-words: "paanch sau rupaye ka 2 kilo
  /// chawal" would otherwise read as 2.
  static double? parse(String input) {
    if (input.trim().isEmpty) return null;
    final tokens = tokenise(input);
    if (tokens.isEmpty) return null;

    final candidates = <_Candidate>[
      ..._digitCandidates(tokens),
      ..._wordCandidates(tokens),
    ];
    if (candidates.isEmpty) return null;

    final adjacent = candidates.where((c) => c.nextToCurrency).toList();
    final pool = adjacent.isNotEmpty ? adjacent : candidates;
    return pool.map((c) => c.value).reduce((a, b) => a > b ? a : b);
  }

  /// Digit-form numbers, applying an adjacent Hindi multiplier ("5 sau" = 500).
  static List<_Candidate> _digitCandidates(List<String> tokens) {
    final out = <_Candidate>[];

    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(token)) continue;

      var value = double.tryParse(token);
      if (value == null) continue;

      final next = i + 1 < tokens.length ? tokens[i + 1] : null;
      final prev = i > 0 ? tokens[i - 1] : null;

      if (next != null && _multipliers.containsKey(next)) {
        value *= _multipliers[next]!;
      }

      out.add(_Candidate(
        value,
        nextToCurrency: (next != null && currencyWords.contains(next)) ||
            (prev != null && currencyWords.contains(prev)),
      ));
    }
    return out;
  }

  /// Word-form numbers, segmented into runs.
  ///
  /// Runs matter: "paanch kilo chawal teen sau" is two separate numbers, and
  /// accumulating across the whole sentence would read it as 800 instead of
  /// 300. Any token that is not part of a number closes the current run.
  static List<_Candidate> _wordCandidates(List<String> tokens) {
    final out = <_Candidate>[];

    var total = 0.0;
    var current = 0.0;
    var inRun = false;
    var pendingHalf = false;
    var nextToCurrency = false;

    void closeRun() {
      if (inRun) {
        final value = total + current;
        if (value > 0) {
          out.add(_Candidate(value, nextToCurrency: nextToCurrency));
        }
      }
      total = 0;
      current = 0;
      inRun = false;
      pendingHalf = false;
      nextToCurrency = false;
    }

    for (final token in tokens) {
      // A currency word sits inside the amount phrase: it adds no value and
      // does not break the run, but it does mark the run as the amount.
      if (currencyWords.contains(token)) {
        if (inRun) nextToCurrency = true;
        continue;
      }

      if (token == 'saade' || token == 'साढ़े' || token == 'साढे') {
        pendingHalf = true;
        inRun = true;
        continue;
      }

      final fraction = _fractions[token];
      if (fraction != null && fraction > 0) {
        current += fraction;
        inRun = true;
        continue;
      }

      final unit = _units[token];
      if (unit != null) {
        current += unit + (pendingHalf ? 0.5 : 0);
        pendingHalf = false;
        inRun = true;
        continue;
      }

      final multiplier = _multipliers[token];
      if (multiplier != null) {
        if (current == 0) current = 1;
        if (multiplier >= 1000) {
          total += current * multiplier;
          current = 0;
        } else {
          current *= multiplier;
        }
        inRun = true;
        continue;
      }

      closeRun();
    }
    closeRun();

    return out;
  }
}

/// One parsed number and whether it sat next to a currency word.
class _Candidate {
  const _Candidate(this.value, {required this.nextToCurrency});

  final double value;
  final bool nextToCurrency;
}
