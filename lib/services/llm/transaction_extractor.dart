import '../extraction/transaction_draft.dart';
import '../../models/ledger_transaction.dart';

/// Turns free text (an ASR transcript or an OCR'd khata page) into candidate
/// ledger entries.
///
/// Two implementations ship:
///   * [RuleBasedExtractor]  - dependency-free, deterministic, always available
///   * FllamaExtractor       - Gemma-2B GGUF via llama.cpp, opt-in
///
/// [AiRuntime] picks the best one available at startup and falls back to the
/// rule-based one if the native model is missing or errors, so a failed model
/// load degrades the quality of extraction rather than breaking the app.
abstract class TransactionExtractor {
  /// Shown in the UI so the demo can honestly say which engine ran.
  String get engineName;

  /// Whether this engine is ready to serve requests.
  Future<bool> isAvailable();

  /// One utterance -> one candidate entry (the voice flow).
  Future<TransactionDraft> extractSingle(
    String text, {
    List<String> knownCustomers = const [],
    TxSource source = TxSource.voice,
  });

  /// A whole khata page -> many candidate entries (the camera flow).
  Future<List<TransactionDraft>> extractBatch(
    String text, {
    List<String> knownCustomers = const [],
    TxSource source = TxSource.cameraScan,
  });

  Future<void> dispose() async {}
}
