import 'package:flutter_test/flutter_test.dart';
import 'package:khatasetu/services/model_manager.dart';

/// These guard the check that actually bit: an `adb push` interrupted half way
/// leaves a file with a valid header, which the app then hands to native code.
void main() {
  const gguf = [0x47, 0x47, 0x55, 0x46];
  const ggml = [0x6C, 0x6D, 0x67, 0x67];

  group('model validation', () {
    test('accepts a complete, correctly-formatted model', () {
      expect(
        ModelManager.validate(
          sizeBytes: ModelManager.llmSpec.minBytes + 1,
          head: gguf,
          spec: ModelManager.llmSpec,
        ),
        isNull,
      );
    });

    test('rejects a truncated file even though its magic bytes are valid', () {
      // The real case: 320 MB of a 1.6 GB Gemma, header intact.
      final problem = ModelManager.validate(
        sizeBytes: 320 * 1024 * 1024,
        head: gguf,
        spec: ModelManager.llmSpec,
      );
      expect(problem, isNotNull);
      expect(problem, contains('incomplete'));
      expect(problem, contains('re-push'));
    });

    test('size is checked before magic, so truncation is named accurately', () {
      // A truncated file with a good header must read as "incomplete",
      // not as "not a valid file" - the message tells the user what to do.
      expect(
        ModelManager.validate(sizeBytes: 1, head: gguf, spec: ModelManager.llmSpec),
        contains('incomplete'),
      );
    });

    test('rejects a complete file of the wrong format', () {
      expect(
        ModelManager.validate(
          sizeBytes: ModelManager.llmSpec.minBytes + 1,
          head: const [0x50, 0x4B, 0x03, 0x04], // a zip
          spec: ModelManager.llmSpec,
        ),
        contains('not a valid'),
      );
    });

    test('rejects a file too short to even hold its magic', () {
      expect(
        ModelManager.validate(
          sizeBytes: ModelManager.asrSpec.minBytes + 1,
          head: const [0x6C, 0x6D],
          spec: ModelManager.asrSpec,
        ),
        contains('not a valid'),
      );
    });

    test('accepts a real whisper header', () {
      expect(
        ModelManager.validate(
          sizeBytes: 74 * 1024 * 1024,
          head: ggml,
          spec: ModelManager.asrSpec,
        ),
        isNull,
      );
    });
  });

  group('specs', () {
    test('magic bytes match the formats actually observed on disk', () {
      expect(ModelManager.llmSpec.magic, gguf);
      expect(ModelManager.asrSpec.magic, ggml);
    });

    test('size floors sit below the real models but above a partial push', () {
      // whisper-tiny is ~74 MB; Gemma-2-2b Q4_K_M is ~1.6 GB.
      expect(ModelManager.asrSpec.minBytes, lessThan(74 * 1024 * 1024));
      expect(ModelManager.llmSpec.minBytes, lessThan(1600 * 1024 * 1024));
      expect(ModelManager.llmSpec.minBytes, greaterThan(320 * 1024 * 1024));
    });
  });
}
