/// Result of an on-device speech-to-text run.
class AsrResult {
  final String text;
  final Duration processingTime;
  final String engineName;

  /// Language the model reported, when it detects one.
  final String? detectedLanguage;

  const AsrResult({
    required this.text,
    required this.processingTime,
    required this.engineName,
    this.detectedLanguage,
  });

  bool get isEmpty => text.trim().isEmpty;
}

/// On-device speech-to-text.
///
/// The only implementation is whisper.cpp (opt-in, see docs/NATIVE_AI.md).
/// When no engine is available the voice screen falls back to a text field
/// rather than blocking the entry — the shopkeeper can still record their
/// khata, just by typing.
abstract class AsrService {
  String get engineName;

  /// Whether a model is loaded and ready.
  Future<bool> isAvailable();

  /// Transcribe a recorded WAV file.
  ///
  /// [language] is an ISO-639-1 code ('hi', 'en') or null to auto-detect.
  /// Passing an explicit language noticeably improves whisper-tiny's accuracy
  /// versus letting it guess, so the app always passes one.
  Future<AsrResult> transcribe(String wavPath, {String? language});

  Future<void> dispose() async {}
}

/// Thrown when transcription fails in a way the UI should explain.
class AsrException implements Exception {
  final String message;
  final Object? cause;
  const AsrException(this.message, [this.cause]);

  @override
  String toString() => 'AsrException: $message';
}
