import '../../models/ledger_transaction.dart';

/// A candidate transaction produced by the voice or camera pipeline, before
/// the shopkeeper has confirmed it.
///
/// Every field is nullable and every field is editable in the UI. This type
/// exists precisely so that a bad ASR result or a hallucinated field can never
/// reach the database unreviewed.
class TransactionDraft {
  TransactionDraft({
    this.customerName,
    this.amount,
    this.item,
    this.direction = TxDirection.credit,
    required this.source,
    this.rawInput,
    this.confidence = DraftConfidence.low,
    this.warnings = const [],
  });

  String? customerName;
  double? amount;
  String? item;
  TxDirection direction;
  final TxSource source;

  /// The transcript or OCR line this came from — shown as "what I heard".
  final String? rawInput;

  DraftConfidence confidence;

  /// Human-readable notes about what the extractor was unsure of.
  final List<String> warnings;

  /// Whether this draft has the minimum needed to save.
  bool get isComplete =>
      (customerName?.trim().isNotEmpty ?? false) &&
      amount != null &&
      amount! > 0;

  /// Fields the shopkeeper still needs to fill in.
  List<String> get missingFields => [
        if (!(customerName?.trim().isNotEmpty ?? false)) 'customer name',
        if (amount == null || amount! <= 0) 'amount',
      ];

  LedgerTransaction toTransaction(int customerId) {
    if (!isComplete) {
      throw StateError('Draft is missing: ${missingFields.join(', ')}');
    }
    return LedgerTransaction(
      customerId: customerId,
      amount: amount!,
      direction: direction,
      itemDescription: (item?.trim().isEmpty ?? true) ? null : item!.trim(),
      source: source,
      createdAt: DateTime.now(),
      rawInputRef: rawInput,
    );
  }

  TransactionDraft copy() => TransactionDraft(
        customerName: customerName,
        amount: amount,
        item: item,
        direction: direction,
        source: source,
        rawInput: rawInput,
        confidence: confidence,
        warnings: List.of(warnings),
      );
}

/// How much the pipeline trusts its own output. Drives whether the UI
/// pre-selects the row and how loudly it asks for a check.
enum DraftConfidence { high, medium, low }

extension DraftConfidenceX on DraftConfidence {
  String get label {
    switch (this) {
      case DraftConfidence.high:
        return 'Looks clear';
      case DraftConfidence.medium:
        return 'Please check';
      case DraftConfidence.low:
        return 'Needs your check';
    }
  }
}
