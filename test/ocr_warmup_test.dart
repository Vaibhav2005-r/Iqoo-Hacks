import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:khatasetu/services/ocr_service.dart';

/// The warm-up image is an embedded base64 literal, and a broken one would
/// fail silently — warmUp swallows its errors by design, so the only symptom
/// would be the 18.8 s cold scan quietly coming back.
void main() {
  group('OCR warm-up image', () {
    test('decodes to a valid PNG', () {
      final bytes = base64Decode(OcrService.warmUpPngBase64);
      expect(
        bytes.sublist(0, 8),
        [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
        reason: 'PNG magic bytes',
      );
    });

    test('is 64x64, as the IHDR header declares', () {
      final bytes = base64Decode(OcrService.warmUpPngBase64);
      // IHDR width and height are big-endian uint32 at offsets 16 and 20.
      int u32(int o) =>
          (bytes[o] << 24) | (bytes[o + 1] << 16) | (bytes[o + 2] << 8) | bytes[o + 3];
      expect(u32(16), 64);
      expect(u32(20), 64);
    });

    test('stays small enough to be a free thing to ship', () {
      expect(base64Decode(OcrService.warmUpPngBase64).length, lessThan(1024));
    });
  });
}
