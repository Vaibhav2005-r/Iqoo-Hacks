#!/usr/bin/env bash
# Reverts to the rules-only extractor. Use this if the native build breaks and
# you need a working app back immediately.
set -euo pipefail

cd "$(dirname "$0")/.."
BACKUP="lib/services/native_ai_bindings.dart.rules-only"

if [ -f "$BACKUP" ]; then
  cp "$BACKUP" lib/services/native_ai_bindings.dart
  echo "Restored rules-only bindings"
else
  echo "No backup found; rewriting a rules-only stub"
  cat > lib/services/native_ai_bindings.dart <<'STUB'
import 'asr/asr_service.dart';
import 'llm/transaction_extractor.dart';

class NativeAiBindings {
  const NativeAiBindings._();
  static const bool enabled = false;
  static Future<TransactionExtractor?> createExtractor() async => null;
  static Future<AsrService?> createAsr() async => null;
}
STUB
fi

rm -rf lib/native_ai
python3 - <<'PY'
import pathlib, re
f = pathlib.Path('pubspec.yaml')
s = f.read_text()
for line in ['  fllama:', '    git:', '      url: https://github.com/Telosnex/fllama.git',
             '      ref: main', '  whisper_flutter_new: ^1.0.1']:
    s = s.replace('\n' + line + '\n', '\n  # ' + line.strip() + '\n')
f.write_text(s)
PY
echo "Run: flutter pub get"
