import 'package:flutter_test/flutter_test.dart';
import 'package:khatasetu/services/asr/asr_service.dart';

/// Whisper does not return "" for silence — it returns bracketed non-speech
/// tokens. Observed on-device: two seconds of nothing transcribed as "(X2)",
/// which reached the confirmation card as if it were something the shopkeeper
/// had said.
void main() {
  group('non-speech transcripts', () {
    test('whisper annotations count as empty', () {
      for (final s in [
        '(X2)',
        '[BLANK_AUDIO]',
        '[Music]',
        '(silence)',
        '[ Silence ]',
        '♪',
        '♪♪♪',
        '[BLANK_AUDIO] [BLANK_AUDIO]',
        '(X2) (X2)',
      ]) {
        expect(AsrResult.looksLikeNonSpeech(s), isTrue, reason: s);
      }
    });

    test('plain empty and whitespace count as empty', () {
      expect(AsrResult.looksLikeNonSpeech(''), isTrue);
      expect(AsrResult.looksLikeNonSpeech('   '), isTrue);
      expect(AsrResult.looksLikeNonSpeech('... !'), isTrue);
    });

    test('real speech does not', () {
      for (final s in [
        'Sharma ji ko paanch sau ka udhar diya',
        'शर्मा जी को पांच सौ का उधार दिया',
        '500',
        'Priya paid 200',
      ]) {
        expect(AsrResult.looksLikeNonSpeech(s), isFalse, reason: s);
      }
    });

    test('speech alongside an annotation is still speech', () {
      // Whisper often prefixes a real utterance with a noise marker; throwing
      // the whole transcript away there would lose a genuine entry.
      expect(
        AsrResult.looksLikeNonSpeech('[BLANK_AUDIO] Sharma ji ko 500 diya'),
        isFalse,
      );
    });

    test('AsrResult.isEmpty uses it', () {
      const r = AsrResult(
        text: '(X2)',
        processingTime: Duration(seconds: 7),
        engineName: 'whisper-tiny',
      );
      expect(r.isEmpty, isTrue);
    });
  });
}
