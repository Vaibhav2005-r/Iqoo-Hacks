import '../models/ledger_transaction.dart';
import 'asr/asr_service.dart';
import 'extraction/transaction_draft.dart';
import 'llm/rule_based_extractor.dart';
import 'llm/transaction_extractor.dart';
import 'native_ai_bindings.dart';

/// Chooses which on-device engines to run, and degrades instead of failing.
///
/// Startup order for extraction:
///   1. the native LLM (Gemma-2B GGUF via llama.cpp), if compiled in and the
///      model file is on the device;
///   2. the rule-based extractor, always.
///
/// At request time the LLM is tried first and the rule-based extractor is
/// used to repair its output: if the model returns nothing, malformed JSON, or
/// a draft with no amount, the deterministic result is used instead. That is
/// the concrete implementation of "never let an LLM parsing failure block the
/// save action".
class AiRuntime {
  AiRuntime._();

  static final AiRuntime instance = AiRuntime._();

  static const _fallbackExtractor = RuleBasedExtractor();

  TransactionExtractor? _nativeExtractor;
  AsrService? _asr;
  bool _initialised = false;

  bool get isInitialised => _initialised;

  /// True when a real LLM is loaded, not just the rule engine.
  bool get hasNativeLlm => _nativeExtractor != null;

  bool get hasAsr => _asr != null;

  AsrService? get asr => _asr;

  /// Name shown in the UI so the demo never overstates what ran.
  String get extractionEngineName =>
      _nativeExtractor?.engineName ?? _fallbackExtractor.engineName;

  String get asrEngineName => _asr?.engineName ?? 'Not available';

  Future<void> initialise() async {
    if (_initialised) return;
    _initialised = true;

    if (!NativeAiBindings.enabled) return;

    // A missing model file or a native crash must not take the app down with
    // it; losing the LLM is survivable, losing the app on stage is not.
    try {
      final extractor = await NativeAiBindings.createExtractor();
      if (extractor != null && await extractor.isAvailable()) {
        _nativeExtractor = extractor;
      }
    } on Object catch (e) {
      _nativeExtractor = null;
      // ignore: avoid_print
      print('[AiRuntime] LLM unavailable, using rules only: $e');
    }

    try {
      final asr = await NativeAiBindings.createAsr();
      if (asr != null && await asr.isAvailable()) {
        _asr = asr;
      }
    } on Object catch (e) {
      _asr = null;
      // ignore: avoid_print
      print('[AiRuntime] ASR unavailable: $e');
    }
  }

  /// Extract one entry from an utterance, with the rule engine as a repair
  /// pass over the LLM's output.
  Future<TransactionDraft> extractSingle(
    String text, {
    List<String> knownCustomers = const [],
    TxSource source = TxSource.voice,
  }) async {
    final rules = await _fallbackExtractor.extractSingle(
      text,
      knownCustomers: knownCustomers,
      source: source,
    );

    final native = _nativeExtractor;
    if (native == null) return rules;

    try {
      final llm = await native.extractSingle(
        text,
        knownCustomers: knownCustomers,
        source: source,
      );
      return _merge(llm, rules);
    } on Object catch (e) {
      // ignore: avoid_print
      print('[AiRuntime] LLM extraction failed, using rules: $e');
      return rules;
    }
  }

  Future<List<TransactionDraft>> extractBatch(
    String text, {
    List<String> knownCustomers = const [],
    TxSource source = TxSource.cameraScan,
  }) async {
    final rules = await _fallbackExtractor.extractBatch(
      text,
      knownCustomers: knownCustomers,
      source: source,
    );

    final native = _nativeExtractor;
    if (native == null) return rules;

    try {
      final llm = await native.extractBatch(
        text,
        knownCustomers: knownCustomers,
        source: source,
      );
      // On a page scan the LLM usually segments rows better than line
      // splitting does, but if it returns obviously less than the rule pass
      // found, the rule pass is the safer answer — a dropped row is a debt
      // the shopkeeper silently loses.
      return llm.length >= rules.length ? llm : rules;
    } on Object catch (e) {
      // ignore: avoid_print
      print('[AiRuntime] LLM batch extraction failed, using rules: $e');
      return rules;
    }
  }

  /// Fills gaps in the LLM's draft from the deterministic one.
  ///
  /// The LLM is better at names and item descriptions; the rule parser is more
  /// reliable on amounts, because it cannot invent a number that was not said.
  static TransactionDraft _merge(
    TransactionDraft llm,
    TransactionDraft rules,
  ) {
    final merged = llm.copy();

    if (merged.amount == null || merged.amount! <= 0) {
      merged.amount = rules.amount;
    }
    if ((merged.customerName?.trim().isEmpty ?? true)) {
      merged.customerName = rules.customerName;
    }
    if ((merged.item?.trim().isEmpty ?? true)) {
      merged.item = rules.item;
    }

    // Disagreement on direction is a genuine ambiguity, so say so rather than
    // silently picking a winner.
    if (merged.direction != rules.direction) {
      merged.confidence = DraftConfidence.low;
      merged.warnings.add(
        'Unclear whether this was udhar given or a payment received',
      );
    } else if (merged.isComplete) {
      merged.confidence = DraftConfidence.high;
    }

    return merged;
  }

  Future<void> dispose() async {
    await _nativeExtractor?.dispose();
    await _asr?.dispose();
    _nativeExtractor = null;
    _asr = null;
    _initialised = false;
  }
}
