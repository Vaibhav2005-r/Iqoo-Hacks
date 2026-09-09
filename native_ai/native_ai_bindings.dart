// Placed at lib/services/native_ai_bindings.dart by scripts/enable_native_ai.sh.
// Import paths below are written for that destination, not for this folder,
// which is why native_ai/ is excluded from analysis in analysis_options.yaml.
import 'asr/asr_service.dart';
import 'llm/transaction_extractor.dart';
import '../native_ai/fllama_extractor.dart';
import '../native_ai/whisper_asr_service.dart';

/// ENABLED version of the native AI bindings.
///
/// Everything downstream ([AiRuntime] and the screens) is unchanged — it only
/// ever sees the interfaces, so turning native AI on or off is this one file.
class NativeAiBindings {
  const NativeAiBindings._();

  static const bool enabled = true;

  static Future<TransactionExtractor?> createExtractor() async {
    final extractor = FllamaExtractor();
    return await extractor.isAvailable() ? extractor : null;
  }

  static Future<AsrService?> createAsr() async {
    final asr = WhisperAsrService();
    return await asr.isAvailable() ? asr : null;
  }
}
