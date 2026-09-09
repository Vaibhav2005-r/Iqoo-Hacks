import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where a model file is expected and whether it is actually there.
class ModelStatus {
  final String label;
  final String fileName;
  final String expectedPath;
  final bool exists;
  final int sizeBytes;

  const ModelStatus({
    required this.label,
    required this.fileName,
    required this.expectedPath,
    required this.exists,
    required this.sizeBytes,
  });

  String get sizeLabel {
    if (!exists) return 'not found';
    final mb = sizeBytes / (1024 * 1024);
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(2)} GB';
    return '${mb.toStringAsFixed(0)} MB';
  }
}

/// Locates the GGUF / ggml model files on the device.
///
/// Models are pushed with `adb push` before the demo rather than bundled in
/// the APK (they are 1-2 GB) or downloaded in-app (that would put a network
/// dependency on stage, which is exactly what this product claims not to
/// need). See docs/MODELS.md for the push commands.
class ModelManager {
  ModelManager._();

  static final ModelManager instance = ModelManager._();

  static const llmFileName = 'gemma-2b-it-q4_k_m.gguf';
  static const asrFileName = 'ggml-tiny.bin';

  Directory? _modelsDir;

  /// App-private external storage, which `adb push` can write to without root
  /// and which survives app restarts.
  Future<Directory> modelsDirectory() async {
    if (_modelsDir != null) return _modelsDir!;

    Directory base;
    if (Platform.isAndroid) {
      base = await getExternalStorageDirectory() ??
          await getApplicationSupportDirectory();
    } else {
      base = await getApplicationSupportDirectory();
    }

    final dir = Directory(p.join(base.path, 'models'));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return _modelsDir = dir;
  }

  Future<String> llmPath() async =>
      p.join((await modelsDirectory()).path, llmFileName);

  Future<String> asrPath() async =>
      p.join((await modelsDirectory()).path, asrFileName);

  Future<ModelStatus> _status(String label, String fileName) async {
    final path = p.join((await modelsDirectory()).path, fileName);
    final file = File(path);
    final exists = file.existsSync();
    return ModelStatus(
      label: label,
      fileName: fileName,
      expectedPath: path,
      exists: exists,
      sizeBytes: exists ? await file.length() : 0,
    );
  }

  Future<ModelStatus> llmStatus() async => _status('Language model', llmFileName);

  Future<ModelStatus> asrStatus() async => _status('Speech model', asrFileName);

  Future<List<ModelStatus>> allStatuses() async => [
        await llmStatus(),
        await asrStatus(),
      ];
}
