import 'asr/asr_service.dart';
import 'llm/transaction_extractor.dart';

/// The single swap point between "rules only" and "real on-device models".
///
/// This default version has no native dependencies, so the app always
/// compiles and always runs end-to-end. `scripts/enable_native_ai.sh`
/// replaces this one file with the version in `native_ai/`, which constructs
/// the llama.cpp and whisper.cpp backed services.
///
/// Why a file swap rather than a plain `if` on a dependency: Dart has no
/// conditional imports for pub packages that may be absent, so any direct
/// `import 'package:fllama/...'` inside lib/ would make a failed native build
/// break compilation of the entire app. Keeping that import out of lib/ until
/// it is proven on the device means a broken NDK build costs us the LLM, not
/// the demo.
class NativeAiBindings {
  const NativeAiBindings._();

  /// Flipped to true by the enabled version of this file.
  static const bool enabled = false;

  /// Returns null when native AI is not compiled in.
  static Future<TransactionExtractor?> createExtractor() async => null;

  static Future<AsrService?> createAsr() async => null;
}
