import 'package:whisper_flutter_new/whisper_flutter_new.dart';

import '../services/asr/asr_service.dart';
import '../services/model_manager.dart';

/// On-device speech-to-text via whisper.cpp (multilingual tiny).
///
/// Lives outside lib/ until enabled — see FllamaExtractor for the reasoning.
///
/// Accuracy note, stated plainly because the demo depends on knowing it:
/// whisper-tiny multilingual is noticeably weaker on Hindi than the .en models
/// are on English. The product answer is not to hide that — it is the
/// confirmation card, which makes a misheard entry a one-tap fix.
class WhisperAsrService implements AsrService {
  WhisperAsrService({this.model = WhisperModel.tiny});

  final WhisperModel model;
  Whisper? _whisper;

  @override
  String get engineName => 'whisper-tiny (on-device)';

  @override
  Future<bool> isAvailable() async {
    final status = await ModelManager.instance.asrStatus();
    if (!status.exists) return false;

    _whisper ??= Whisper(
      model: model,
      // Point at the adb-pushed directory rather than letting the package
      // download a model; the app must work in airplane mode.
      downloadHost: null,
      modelDir: (await ModelManager.instance.modelsDirectory()).path,
    );
    return true;
  }

  @override
  Future<AsrResult> transcribe(String wavPath, {String? language}) async {
    final whisper = _whisper;
    if (whisper == null) {
      throw const AsrException('Speech model is not loaded');
    }

    final stopwatch = Stopwatch()..start();
    try {
      final result = await whisper.transcribe(
        transcribeRequest: TranscribeRequest(
          audio: wavPath,
          // Passing an explicit language beats auto-detect on tiny models,
          // which frequently mis-detect short Hindi utterances as Urdu/Nepali.
          language: language ?? 'hi',
          isTranslate: false,
          isNoTimestamps: true,
          splitOnWord: false,
        ),
      );
      stopwatch.stop();

      return AsrResult(
        text: result.text.trim(),
        processingTime: stopwatch.elapsed,
        engineName: engineName,
        detectedLanguage: language,
      );
    } on Object catch (e) {
      stopwatch.stop();
      throw AsrException('Could not transcribe the recording', e);
    }
  }

  @override
  Future<void> dispose() async {
    _whisper = null;
  }
}
