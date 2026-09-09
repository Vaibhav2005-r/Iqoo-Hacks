/// Which way money/goods moved.
///
/// CREDIT  = shopkeeper gave goods or money on credit (udhar). Customer's
///           balance goes UP — they owe more.
/// PAYMENT = customer paid back. Balance goes DOWN.
enum TxDirection { credit, payment }

/// Where the entry came from. Kept so the Credit Passport can honestly say
/// how much of the ledger was voice-captured vs scanned vs typed.
enum TxSource { voice, cameraScan, manual }

extension TxDirectionX on TxDirection {
  String get dbValue => this == TxDirection.credit ? 'CREDIT' : 'PAYMENT';

  /// Sign applied to the amount when accumulating a balance.
  int get balanceSign => this == TxDirection.credit ? 1 : -1;

  String get label => this == TxDirection.credit ? 'Udhar given' : 'Payment received';

  static TxDirection fromDb(String value) =>
      value.toUpperCase() == 'PAYMENT' ? TxDirection.payment : TxDirection.credit;
}

extension TxSourceX on TxSource {
  String get dbValue {
    switch (this) {
      case TxSource.voice:
        return 'VOICE';
      case TxSource.cameraScan:
        return 'CAMERA_SCAN';
      case TxSource.manual:
        return 'MANUAL';
    }
  }

  String get label {
    switch (this) {
      case TxSource.voice:
        return 'Voice';
      case TxSource.cameraScan:
        return 'Scanned';
      case TxSource.manual:
        return 'Typed';
    }
  }

  static TxSource fromDb(String value) {
    switch (value.toUpperCase()) {
      case 'VOICE':
        return TxSource.voice;
      case 'CAMERA_SCAN':
        return TxSource.cameraScan;
      default:
        return TxSource.manual;
    }
  }
}

/// One ledger entry.
///
/// Named `LedgerTransaction` rather than `Transaction` on purpose: `sqflite`
/// exports a `Transaction` class, and importing both would collide in every
/// DAO file.
class LedgerTransaction {
  final int? id;
  final int customerId;
  final double amount;
  final TxDirection direction;
  final String? itemDescription;
  final TxSource source;
  final DateTime createdAt;

  /// The transcript or OCR text this entry was extracted from. Kept for
  /// debugging the AI pipeline and for showing "what I heard" in the UI.
  final String? rawInputRef;

  const LedgerTransaction({
    this.id,
    required this.customerId,
    required this.amount,
    required this.direction,
    this.itemDescription,
    required this.source,
    required this.createdAt,
    this.rawInputRef,
  });

  /// Signed contribution to a running balance (positive = customer owes more).
  double get signedAmount => amount * direction.balanceSign;

  LedgerTransaction copyWith({
    int? id,
    int? customerId,
    double? amount,
    TxDirection? direction,
    String? itemDescription,
    TxSource? source,
    DateTime? createdAt,
    String? rawInputRef,
  }) {
    return LedgerTransaction(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      amount: amount ?? this.amount,
      direction: direction ?? this.direction,
      itemDescription: itemDescription ?? this.itemDescription,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      rawInputRef: rawInputRef ?? this.rawInputRef,
    );
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'customer_id': customerId,
        'amount': amount,
        'direction': direction.dbValue,
        'item_description': itemDescription,
        'source': source.dbValue,
        'created_at': createdAt.millisecondsSinceEpoch,
        'raw_input_ref': rawInputRef,
      };

  factory LedgerTransaction.fromMap(Map<String, Object?> map) {
    return LedgerTransaction(
      id: map['id'] as int?,
      customerId: map['customer_id'] as int,
      amount: (map['amount'] as num).toDouble(),
      direction: TxDirectionX.fromDb(map['direction'] as String),
      itemDescription: map['item_description'] as String?,
      source: TxSourceX.fromDb(map['source'] as String),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      rawInputRef: map['raw_input_ref'] as String?,
    );
  }
}
