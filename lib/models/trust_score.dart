import 'dart:convert';

/// One scoring component, carrying enough context for the Credit Passport to
/// explain itself. The transparency is the product — never collapse this into
/// a bare number.
class ScoreComponent {
  final String key;
  final String label;
  final double earned;
  final double maxPoints;

  /// Plain-language reason, e.g. "8 of 10 udhar entries were paid back".
  final String explanation;

  const ScoreComponent({
    required this.key,
    required this.label,
    required this.earned,
    required this.maxPoints,
    required this.explanation,
  });

  double get ratio => maxPoints <= 0 ? 0 : (earned / maxPoints).clamp(0.0, 1.0);

  Map<String, Object?> toJson() => {
        'key': key,
        'label': label,
        'earned': earned,
        'max_points': maxPoints,
        'explanation': explanation,
      };

  factory ScoreComponent.fromJson(Map<String, Object?> json) => ScoreComponent(
        key: json['key'] as String,
        label: json['label'] as String,
        earned: (json['earned'] as num).toDouble(),
        maxPoints: (json['max_points'] as num).toDouble(),
        explanation: (json['explanation'] as String?) ?? '',
      );
}

/// A computed trust score plus the components that produced it.
class TrustScoreSnapshot {
  final int? id;
  final int shopId;

  /// Raw 0-100 score.
  final double score;

  final DateTime computedAt;
  final List<ScoreComponent> components;

  const TrustScoreSnapshot({
    this.id,
    required this.shopId,
    required this.score,
    required this.computedAt,
    required this.components,
  });

  /// Rescaled to a familiar 300-850 credit-score-shaped range, purely for
  /// legibility on the passport. The honest 0-100 value is always shown too.
  int get displayScore => (300 + (score.clamp(0, 100) / 100.0) * 550).round();

  /// Coarse band used for colour and copy.
  ScoreBand get band {
    if (score >= 75) return ScoreBand.strong;
    if (score >= 50) return ScoreBand.building;
    if (score >= 25) return ScoreBand.early;
    return ScoreBand.insufficient;
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'shop_id': shopId,
        'score': score,
        'computed_at': computedAt.millisecondsSinceEpoch,
        'inputs_json': jsonEncode(components.map((c) => c.toJson()).toList()),
      };

  factory TrustScoreSnapshot.fromMap(Map<String, Object?> map) {
    final rawInputs = map['inputs_json'] as String?;
    final decoded = (rawInputs == null || rawInputs.isEmpty)
        ? const <dynamic>[]
        : jsonDecode(rawInputs) as List<dynamic>;

    return TrustScoreSnapshot(
      id: map['id'] as int?,
      shopId: map['shop_id'] as int,
      score: (map['score'] as num).toDouble(),
      computedAt: DateTime.fromMillisecondsSinceEpoch(
        map['computed_at'] as int,
      ),
      components: decoded
          .map((e) => ScoreComponent.fromJson(e as Map<String, Object?>))
          .toList(),
    );
  }
}

enum ScoreBand { insufficient, early, building, strong }

extension ScoreBandX on ScoreBand {
  String get label {
    switch (this) {
      case ScoreBand.insufficient:
        return 'Not enough history yet';
      case ScoreBand.early:
        return 'Early history';
      case ScoreBand.building:
        return 'Building credit';
      case ScoreBand.strong:
        return 'Strong credit behaviour';
    }
  }

  /// Copy aimed at the shopkeeper, not the lender.
  String get guidance {
    switch (this) {
      case ScoreBand.insufficient:
        return 'Keep recording entries for a few weeks to build a score a lender can read.';
      case ScoreBand.early:
        return 'A good start. Recording payments as well as udhar raises this fastest.';
      case ScoreBand.building:
        return 'Your ledger already shows a consistent repayment pattern.';
      case ScoreBand.strong:
        return 'Your ledger shows steady, well-repaid credit over time.';
    }
  }
}
