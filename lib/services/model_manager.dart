import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// What a model file must look like to be worth handing to native code.
class ModelSpec {
  const ModelSpec({
    required this.label,
    required this.fileName,
    required this.magic,
    required this.minBytes,
  });

  final String label;
  final String fileName;

  /// Leading bytes the format guarantees. Catches the wrong file entirely.
  final List<int> magic;

  /// Smallest plausible size for this model.
  ///
  /// This is the check that matters in practice. An `adb push` interrupted
  /// half way leaves a file with a perfectly valid header — observed here as
  /// exactly 320 MB of a 1.6 GB Gemma — so magic bytes alone happily pass it
  /// through to llama.cpp, which then crashes or hangs on load.
  final int minBytes;
}

/// Where a model file is expected and whether it is actually usable.
class ModelStatus {
  final String label;
  final String fileName;
  final String expectedPath;
  final bool exists;
  final int sizeBytes;

  /// Null when the file is fine; otherwise why it cannot be trusted.
  final String? problem;

  const ModelStatus({
    required this.label,
    required this.fileName,
    required this.expectedPath,
    required this.exists,
    required this.sizeBytes,
    this.problem,
  });

  /// Only a present AND intact file should ever reach native code.
  bool get isUsable => exists && problem == null;

  String get sizeLabel {
    if (!exists) return 'not found';
    if (problem != null) return problem!;
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

  /// Gemma-2-2b-it rather than the original Gemma-2b-it: Google's own GGUF
  /// repo is gated (HTTP 401 without an access token), while community quants
  /// of the newer model are public, the same size class, and better.
  static const llmSpec = ModelSpec(
    label: 'Language model',
    fileName: 'gemma-2-2b-it-Q4_K_M.gguf',
    // 'GGUF'
    magic: [0x47, 0x47, 0x55, 0x46],
    // Q4_K_M of a 2B model is ~1.6 GB; anything under 1.2 GB is a partial push.
    minBytes: 1200 * 1024 * 1024,
  );

  static const asrSpec = ModelSpec(
    label: 'Speech model',
    fileName: 'ggml-tiny.bin',
    // whisper's 0x67676D6C magic, little-endian on disk.
    magic: [0x6C, 0x6D, 0x67, 0x67],
    // tiny is ~74 MB.
    minBytes: 50 * 1024 * 1024,
  );

  static String get llmFileName => llmSpec.fileName;
  static String get asrFileName => asrSpec.fileName;

  /// Decides whether a model file can be trusted, given its size and first
  /// bytes. Pure so it can be tested without a device or a 1.6 GB fixture.
  ///
  /// Order matters: size is checked first because a truncated file keeps a
  /// perfectly valid header, so magic bytes alone would wave it through.
  @visibleForTesting
  static String? validate({
    required int sizeBytes,
    required List<int> head,
    required ModelSpec spec,
  }) {
    if (sizeBytes < spec.minBytes) {
      final mb = (sizeBytes / (1024 * 1024)).round();
      final needMb = (spec.minBytes / (1024 * 1024)).round();
      return 'incomplete — $mb MB, expected at least $needMb MB. '
          'The push was probably interrupted; re-push it.';
    }
    for (var i = 0; i < spec.magic.length; i++) {
      if (i >= head.length || head[i] != spec.magic[i]) {
        return 'not a valid ${spec.fileName.split('.').last} file';
      }
    }
    return null;
  }

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

  Future<ModelStatus> _status(ModelSpec spec) async {
    final path = p.join((await modelsDirectory()).path, spec.fileName);
    final file = File(path);

    if (!file.existsSync()) {
      return ModelStatus(
        label: spec.label,
        fileName: spec.fileName,
        expectedPath: path,
        exists: false,
        sizeBytes: 0,
        problem: 'not found',
      );
    }

    final size = await file.length();
    String? problem;
    try {
      final head = size > 0
          ? await file.openRead(0, spec.magic.length).first
          : const <int>[];
      problem = validate(sizeBytes: size, head: head, spec: spec);
    } on Object catch (e) {
      problem = 'could not be read ($e)';
    }

    return ModelStatus(
      label: spec.label,
      fileName: spec.fileName,
      expectedPath: path,
      exists: true,
      sizeBytes: size,
      problem: problem,
    );
  }

  Future<ModelStatus> llmStatus() async => _status(llmSpec);

  Future<ModelStatus> asrStatus() async => _status(asrSpec);

  Future<List<ModelStatus>> allStatuses() async => [
        await llmStatus(),
        await asrStatus(),
      ];
}
