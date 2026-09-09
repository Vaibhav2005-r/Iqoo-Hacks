import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Microphone capture for the voice-entry flow.
///
/// Records 16 kHz mono WAV because that is exactly what whisper.cpp expects;
/// recording anything else means resampling on the phone before inference,
/// which is pure added latency on the critical path.
class AudioRecorderService {
  AudioRecorderService({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  String? _currentPath;

  static const _config = RecordConfig(
    encoder: AudioEncoder.wav,
    sampleRate: 16000,
    numChannels: 1,
  );

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<bool> get isRecording => _recorder.isRecording();

  /// Starts recording. Returns the file path being written to.
  Future<String> start() async {
    if (!await hasPermission()) {
      throw const AudioRecordingException(
        'Microphone permission is needed to record a khata entry.',
      );
    }

    final dir = await getTemporaryDirectory();
    final path = p.join(
      dir.path,
      'khata_${DateTime.now().millisecondsSinceEpoch}.wav',
    );

    await _recorder.start(_config, path: path);
    _currentPath = path;
    return path;
  }

  /// Stops recording and returns the finished file, or null if nothing usable
  /// was captured.
  Future<String?> stop() async {
    final path = await _recorder.stop() ?? _currentPath;
    _currentPath = null;
    if (path == null) return null;

    final file = File(path);
    if (!file.existsSync()) return null;

    // A WAV header alone is ~44 bytes; anything this small is a mis-tap, not
    // speech, and running it through whisper just wastes seconds on stage.
    if (await file.length() < 4000) {
      await file.delete().catchError((_) => file);
      return null;
    }
    return path;
  }

  Future<void> cancel() async {
    try {
      final path = await _recorder.stop() ?? _currentPath;
      if (path != null) {
        final file = File(path);
        if (file.existsSync()) await file.delete();
      }
    } finally {
      _currentPath = null;
    }
  }

  /// Live input amplitude, used to drive the waveform on the record button.
  Stream<Amplitude> amplitudeStream() =>
      _recorder.onAmplitudeChanged(const Duration(milliseconds: 160));

  Future<void> dispose() async {
    await _recorder.dispose();
  }
}

class AudioRecordingException implements Exception {
  final String message;
  const AudioRecordingException(this.message);

  @override
  String toString() => message;
}
