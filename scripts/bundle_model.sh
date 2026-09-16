#!/usr/bin/env bash
# Copies the whisper model into assets/ so the next build is self-contained.
#
# Without this the APK is ~33 MB and the model must be pushed with adb. With
# it the APK is ~100 MB and voice works the moment it is installed — which is
# what you want for handing a build to someone to test.
#
# The LLM is deliberately NOT bundled: Gemma is 1.6 GB.
set -euo pipefail
cd "$(dirname "$0")/.."

MODEL="${1:-dist/ggml-tiny.bin}"
if [ ! -f "$MODEL" ]; then
  echo "Model not found: $MODEL"
  echo
  echo "Fetch it with:"
  echo "  curl -L -o dist/ggml-tiny.bin \\"
  echo "    https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin"
  exit 1
fi

mkdir -p assets/models
cp "$MODEL" assets/models/ggml-tiny.bin
SIZE=$(du -h assets/models/ggml-tiny.bin | cut -f1)
echo "Bundled assets/models/ggml-tiny.bin ($SIZE)"
echo "Now: flutter build apk --release --split-per-abi"
echo
echo "To go back to a small APK: rm assets/models/ggml-tiny.bin"
