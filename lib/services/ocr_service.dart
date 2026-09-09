import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Raw text lifted off a khata page, kept line-structured.
///
/// Line structure matters: a paper khata is a table, so the line breaks carry
/// real information about which name goes with which amount. Flattening to one
/// blob would throw that away.
class OcrResult {
  final String fullText;
  final List<String> lines;
  final Duration processingTime;

  const OcrResult({
    required this.fullText,
    required this.lines,
    required this.processingTime,
  });

  bool get isEmpty => fullText.trim().isEmpty;
}

/// On-device OCR via ML Kit Text Recognition v2.
///
/// Fully on-device and offline — no image ever leaves the phone.
class OcrService {
  OcrService();

  TextRecognizer? _recognizer;

  /// The Devanagari recogniser also reads Latin script, so a single recogniser
  /// covers a khata page mixing Hindi names with English numerals — which is
  /// what real khata pages look like.
  TextRecognizer get _instance => _recognizer ??= TextRecognizer(
        script: TextRecognitionScript.devanagiri,
      );

  Future<OcrResult> recognise(String imagePath) async {
    final file = File(imagePath);
    if (!file.existsSync()) {
      throw OcrException('Image not found at $imagePath');
    }

    final stopwatch = Stopwatch()..start();
    try {
      final input = InputImage.fromFilePath(imagePath);
      final recognised = await _instance.processImage(input);
      stopwatch.stop();

      // ML Kit groups text into blocks then lines; blocks are returned in
      // roughly reading order, which is what we want for a ledger page.
      final lines = <String>[];
      for (final block in recognised.blocks) {
        for (final line in block.lines) {
          final text = line.text.trim();
          if (text.isNotEmpty) lines.add(text);
        }
      }

      return OcrResult(
        fullText: recognised.text,
        lines: lines,
        processingTime: stopwatch.elapsed,
      );
    } on Exception catch (e) {
      stopwatch.stop();
      throw OcrException('Could not read the page', e);
    }
  }

  Future<void> dispose() async {
    await _recognizer?.close();
    _recognizer = null;
  }
}

class OcrException implements Exception {
  final String message;
  final Object? cause;
  const OcrException(this.message, [this.cause]);

  @override
  String toString() => 'OcrException: $message';
}
