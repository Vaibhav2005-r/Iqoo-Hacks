import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:khatasetu/models/ledger_transaction.dart';
import 'package:khatasetu/services/asr/asr_service.dart';
import 'package:khatasetu/services/llm/rule_based_extractor.dart';
import 'package:khatasetu/services/model_manager.dart';
import 'package:khatasetu/services/native_ai_bindings.dart';
import 'package:path/path.dart' as p;

/// Runs whisper.cpp against real Hindi audio on a real device.
///
/// This is the one thing no unit test and no emulator screenshot could cover:
/// whether speech recognition actually produces a usable transcript, and
/// whether the extractor can read what it produces. Audio files are pushed
/// next to the model rather than recorded, because automation has no voice.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const extractor = RuleBasedExtractor();

  testWidgets('whisper transcribes Hindi and the extractor reads it',
      (tester) async {
    final status = await ModelManager.instance.asrStatus();
    // ignore: avoid_print
    print('[ASR] model: ${status.expectedPath}');
    // ignore: avoid_print
    print('[ASR] usable: ${status.isUsable} (${status.sizeLabel})');
    if (!status.isUsable) {
      // Not a failure: `flutter test integration_test` reinstalls the app on
      // every run, and an uninstall wipes the external files directory that
      // the model lives in. Push the model AFTER the first run installs the
      // app, then run again.
      // ignore: avoid_print
      print('[ASR] SKIPPED - push the model, then re-run without an uninstall');
      return;
    }

    final dir = await ModelManager.instance.modelsDirectory();
    final asr = await _buildAsr();
    expect(asr, isNotNull, reason: 'native ASR not compiled in');

    for (final name in ['p1', 'p2', 'p3']) {
      final wav = File(p.join(dir.path, '$name.wav'));
      if (!wav.existsSync()) {
        // ignore: avoid_print
        print('[ASR] SKIP $name - not pushed');
        continue;
      }

      final sw = Stopwatch()..start();
      final result = await asr!.transcribe(wav.path, language: 'hi');
      sw.stop();

      final draft = await extractor.extractSingle(
        result.text,
        source: TxSource.voice,
      );
      // ignore: avoid_print
      print('[ASR] $name (${sw.elapsedMilliseconds} ms)');
      // ignore: avoid_print
      print('[ASR]   heard : ${result.text}');
      // ignore: avoid_print
      print('[ASR]   parsed: name=${draft.customerName} '
          'amount=${draft.amount} dir=${draft.direction.dbValue}');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/// Built through the bindings so this test works whether or not native AI is
/// compiled in, and reports clearly when it is not.
Future<AsrService?> _buildAsr() async {
  // ignore: avoid_print
  print('[ASR] native AI enabled: ${NativeAiBindings.enabled}');
  return NativeAiBindings.createAsr();
}
