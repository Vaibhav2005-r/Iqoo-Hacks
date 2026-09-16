#!/usr/bin/env bash
# Turns on the real on-device LLM (llama.cpp/Gemma) and ASR (whisper.cpp).
#
# These are OFF by default because their native (NDK/ABI) builds are the most
# likely thing to break, and a broken native build breaks the whole app. Run
# this once you have a device to test on and time to debug a Gradle failure.
#
# Reverse it with: scripts/disable_native_ai.sh
set -euo pipefail

# --asr-only turns on whisper.cpp but NOT llama.cpp. Prefer it: whisper-tiny
# is ~75 MB against ~1.5 GB for Gemma, and fllama is a git dependency with a
# heavier native build, so a problem there should not cost you speech too.
ASR_ONLY=0
if [ "${1:-}" = "--asr-only" ]; then
  ASR_ONLY=1
fi

cd "$(dirname "$0")/.."
BACKUP="lib/services/native_ai_bindings.dart.rules-only"

if [ ! -f "$BACKUP" ]; then
  cp lib/services/native_ai_bindings.dart "$BACKUP"
  echo "Backed up rules-only bindings -> $BACKUP"
fi

mkdir -p lib/native_ai
cp native_ai/whisper_asr_service.dart lib/native_ai/
if [ "$ASR_ONLY" = "1" ]; then
  cp native_ai/native_ai_bindings_asr_only.dart lib/services/native_ai_bindings.dart
  echo "Copied whisper.cpp into lib/ (speech only)"
else
  cp native_ai/fllama_extractor.dart   lib/native_ai/
  cp native_ai/native_ai_bindings.dart lib/services/native_ai_bindings.dart
  echo "Copied whisper.cpp and llama.cpp into lib/"
fi

ASR_ONLY=$ASR_ONLY python3 - <<'PY'
import os
import pathlib

ASR_ONLY = os.environ.get("ASR_ONLY") == "1"

TARGETS = ["  # whisper_flutter_new: ^1.0.1"]
if not ASR_ONLY:
    TARGETS += [
        "  # fllama:",
        "  #   git:",
        "  #     url: https://github.com/Telosnex/fllama.git",
        "  #     ref: f05270b0833371090e6fc76e796061fbc2575226  # pinned; `main` can move under you",
    ]

path = pathlib.Path("pubspec.yaml")
lines = path.read_text().splitlines(keepends=True)
changed = 0

for i, line in enumerate(lines):
    if line.rstrip("\n") in TARGETS:
        # "  # fllama:" -> "  fllama:";  "  #   git:" -> "    git:"
        lines[i] = line.replace("# ", "", 1)
        changed += 1

path.write_text("".join(lines))
print(f"pubspec.yaml: uncommented {changed} dependency line(s)"
      if changed else "pubspec.yaml: already enabled")
PY

echo
echo "Now run:  flutter pub get && flutter run"
echo "If the Android build fails it is almost certainly NDK/ABI - see docs/NATIVE_AI.md"
