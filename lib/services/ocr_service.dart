import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Raw text lifted off a khata page, kept line-structured.
///
/// Line structure matters: a paper khata is a table, so the line breaks carry
/// real information about which name goes with which amount. Flattening to one
/// blob would throw that away.
class OcrResult {
  final String fullText;

  /// Raw recognised lines, in ML Kit's own order.
  final List<String> lines;

  /// Lines regrouped into visual rows by vertical position.
  ///
  /// This is the one the extractor should use. A khata page is a table, and
  /// ML Kit returns each cell as its own line — so "Sharma ji" and "500" come
  /// back separately and a naive newline split loses the very association
  /// that makes the row a transaction.
  final List<String> rows;

  final Duration processingTime;

  const OcrResult({
    required this.fullText,
    required this.lines,
    required this.rows,
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

  bool _warmedUp = false;

  /// A 64x64 greyscale PNG with a couple of dark bars. Content barely matters
  /// — it exists only to give [warmUp] something valid to run through the
  /// pipeline — but bars beat a blank field, which a detector may short
  /// circuit on without ever loading the model.
  @visibleForTesting
  static const warmUpPngBase64 =
      'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAAAAACPAi4CAAAANElEQVR42u3TsREA'
      'MAjEsN9/aVghOTqQB1Dn1LAAAIB1QD4D7AS8AAC8zQS4AXgBAAAAqgEzF3NEtA7g'
      'ZQAAAABJRU5ErkJggg==';
  /// Loads the recognition model before the user needs it.
  ///
  /// ML Kit loads its model on first `processImage`, not at construction, so
  /// the first real scan on a fresh install pays the whole cost: measured at
  /// **18.8 s** on an emulator, against 1.4 s once warm. Running a throwaway
  /// recognition while the shopkeeper is still choosing a photo moves that
  /// off the critical path entirely.
  ///
  /// Best-effort and non-blocking by design. Any failure is swallowed: a
  /// warm-up that does not work must never stop a real scan from being tried,
  /// and the worst case is simply the cold cost we already have today.
  Future<void> warmUp() async {
    if (_warmedUp) return;
    _warmedUp = true;

    File? file;
    try {
      final dir = await getTemporaryDirectory();
      file = File(p.join(dir.path, 'ocr_warmup.png'));
      await file.writeAsBytes(base64Decode(warmUpPngBase64));
      await _instance.processImage(InputImage.fromFilePath(file.path));
    } on Object catch (_) {
      // Deliberately ignored - see above.
    } finally {
      if (file != null && file.existsSync()) {
        try {
          await file.delete();
        } on Object catch (_) {
          // Temp file; the OS will reclaim it.
        }
      }
    }
  }

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

      final lines = <String>[];
      final placed = <_PlacedLine>[];
      for (final block in recognised.blocks) {
        for (final line in block.lines) {
          final text = line.text.trim();
          if (text.isEmpty) continue;
          lines.add(text);
          placed.add(_PlacedLine(text, line.boundingBox));
        }
      }

      return OcrResult(
        fullText: recognised.text,
        lines: lines,
        rows: _groupIntoRows(placed),
        processingTime: stopwatch.elapsed,
      );
    } on Object catch (e) {
      // Object, not Exception: a missing native recogniser surfaces as an
      // Error rather than an Exception, and the scan screen should show a
      // message instead of letting it escape as an unhandled failure.
      stopwatch.stop();
      throw OcrException('Could not read the page', e);
    }
  }

  /// Groups recognised lines into visual rows using their bounding boxes.
  ///
  /// Two lines belong to the same row when their vertical centres are closer
  /// than half a line height — tolerant enough for a page photographed at a
  /// slight angle, tight enough not to merge adjacent ledger rows. Within a
  /// row, lines are ordered left to right so the joined text reads the way the
  /// page does: name, then amount, then note.
  static List<String> _groupIntoRows(List<_PlacedLine> placed) {
    if (placed.isEmpty) return const [];

    final sorted = List<_PlacedLine>.from(placed)
      ..sort((a, b) => a.centreY.compareTo(b.centreY));

    final heights = sorted.map((l) => l.box.height).toList()..sort();
    final medianHeight = heights[heights.length ~/ 2];
    final tolerance = (medianHeight <= 0 ? 12.0 : medianHeight) * 0.5;

    final rows = <List<_PlacedLine>>[];
    var current = <_PlacedLine>[sorted.first];

    for (final line in sorted.skip(1)) {
      if ((line.centreY - current.last.centreY).abs() <= tolerance) {
        current.add(line);
      } else {
        rows.add(current);
        current = [line];
      }
    }
    rows.add(current);

    return rows.map((row) {
      final ordered = List<_PlacedLine>.from(row)
        ..sort((a, b) => a.box.left.compareTo(b.box.left));
      return ordered.map((l) => l.text).join('  ');
    }).toList();
  }

  Future<void> dispose() async {
    await _recognizer?.close();
    _recognizer = null;
    _warmedUp = false;
  }
}

/// A recognised line with the box it occupies on the page.
class _PlacedLine {
  _PlacedLine(this.text, Rect? boundingBox)
      : box = boundingBox ?? Rect.zero;

  final String text;
  final Rect box;

  double get centreY => box.top + box.height / 2;
}

class OcrException implements Exception {
  final String message;
  final Object? cause;
  const OcrException(this.message, [this.cause]);

  @override
  String toString() => 'OcrException: $message';
}
