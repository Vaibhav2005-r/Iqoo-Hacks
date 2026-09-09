# Model files

The GGUF / ggml weights are **not** in this repo and **not** bundled in the
APK. They are 1–2 GB, and downloading them in-app would put a network
dependency on stage — which is exactly what this product claims not to need.

Push them to the device once, before the demo.

## What to get

| Role | File | Source | Size |
|---|---|---|---|
| LLM | `gemma-2b-it-q4_k_m.gguf` | [google/gemma-2b-it-GGUF](https://huggingface.co/google/gemma-2b-it-GGUF) or a community Q4_K_M quant | ~1.5 GB |
| ASR | `ggml-tiny.bin` | [ggerganov/whisper.cpp](https://huggingface.co/ggerganov/whisper.cpp) | ~75 MB |

**Use the multilingual whisper model, not `ggml-tiny.en.bin`.** The `.en`
variants cannot transcribe Hindi at all.

`ModelManager` looks for exactly these filenames. If you use a different quant,
either rename the file or change the constants in
`lib/services/model_manager.dart`.

## Where they go

App-private external storage — `adb push` can write there without root, and it
survives app restarts:

```
/sdcard/Android/data/com.caffeinatedcompilers.khatasetu/files/models/
```

## Pushing

Install and launch the app at least once first, so Android creates the
directory.

```bash
PKG=com.caffeinatedcompilers.khatasetu
DEST=/sdcard/Android/data/$PKG/files/models

adb shell mkdir -p $DEST
adb push gemma-2b-it-q4_k_m.gguf $DEST/
adb push ggml-tiny.bin $DEST/
adb shell ls -lh $DEST
```

The push takes a few minutes over USB 2. Do it well before you need it.

## Checking

The app reads these paths at startup through `ModelManager`. If a file is
missing, `AiRuntime` logs it and falls back to the rule-based extractor rather
than failing — so a silent fallback looks like a working app with worse
extraction. When you expect the LLM to be running, check `logcat`:

```bash
adb logcat | grep AiRuntime
```

`[AiRuntime] LLM unavailable, using rules only: ...` means the model was not
found or failed to load.
