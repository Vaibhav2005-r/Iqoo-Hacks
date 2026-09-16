// Placed at lib/services/native_ai_bindings.dart by
// scripts/enable_native_ai.sh --asr-only.
//
// Import paths below are written for that destination, not for this folder,
// which is why native_ai/ is excluded from analysis in analysis_options.yaml.
import 'asr/asr_service.dart';
import 'llm/transaction_extractor.dart';
import '../native_ai/whisper_asr_service.dart';

/// Native AI bindings with **speech only**.
///
/// whisper.cpp is enabled; llama.cpp is not. The two are independent by
/// design, and enabling them separately is the point: whisper-tiny is ~75 MB
/// against ~1.5 GB for Gemma, and `fllama` is a git dependency with a heavier
/// native build. Turning on the cheaper, higher-value half first means a
/// problem with the LLM cannot cost us speech.
///
/// With no LLM, [AiRuntime] runs the deterministic RuleBasedExtractor over
/// whisper's transcript — which is the same path the typed input already
/// uses, and is already verified end to end.
class NativeAiBindings {
  const NativeAiBindings._();

  static const bool enabled = true;

  /// No LLM in this configuration; AiRuntime falls back to the rule engine.
  static Future<TransactionExtractor?> createExtractor() async => null;

  static Future<AsrService?> createAsr() async {
    final asr = WhisperAsrService();
    return await asr.isAvailable() ? asr : null;
  }
}
