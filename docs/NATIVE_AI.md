# Turning on the native models

By default KhataSetu runs the deterministic `RuleBasedExtractor` and no speech
recognition. Everything works end-to-end in that state. This document is about
switching on llama.cpp and whisper.cpp.

## Why they are off by default

`fllama` and the whisper.cpp Flutter bindings are community-maintained packages
with native NDK builds. NDK/ABI mismatches are the most common failure mode in
this stack, and a failed native build fails compilation of the **whole app** —
not just the feature.

Keeping those imports out of `lib/` until they are proven on the device means a
broken Gradle build costs you the LLM, not the demo. That is the entire reason
for the file-swap design.

## Enabling

```bash
./scripts/enable_native_ai.sh
flutter pub get
flutter run
```

The script:
1. backs up `lib/services/native_ai_bindings.dart` (the rules-only version),
2. copies `native_ai/*.dart` into `lib/native_ai/`,
3. overwrites the bindings file with the version that constructs the real
   services,
4. uncomments the `fllama` and `whisper_flutter_new` dependencies in
   `pubspec.yaml`.

Reverting:

```bash
./scripts/disable_native_ai.sh
flutter pub get
```

Do this the moment the native build starts costing you time. A working app with
rule-based extraction beats a broken app with a better model.

## Verify the API before you trust it

`native_ai/fllama_extractor.dart` and `native_ai/whisper_asr_service.dart` are
written against the APIs as documented, but both packages have moved their APIs
before. Check these against the revision you actually pin:

**fllama** — `OpenAiRequest` field names, the `fllamaChat` callback arity
(`response, responseJson, done`), and whether `grammar` (GBNF) is honoured on
your build. The grammar is what removes malformed-JSON failures by
construction; if it is ignored, the `_decodeObject` brace-slicing fallback
still catches most cases, and `AiRuntime` repairs the rest from the rule
extractor.

**whisper_flutter_new** — the `Whisper(...)` constructor arguments and
`TranscribeRequest` field names. In particular confirm you can point it at the
adb-pushed `modelDir` and prevent it downloading a model; the app must work in
airplane mode.

These files are excluded from analysis (`analysis_options.yaml`) while they sit
in `native_ai/`, because their import paths are written for their post-copy
location. They are only analysed once the enable script has moved them.

## The LLM is off by default, and that is a build-system constraint

`whisper_flutter_new` uses a normal Gradle/NDK build, so having it on costs
nothing: `flutter test` is unaffected. It ships enabled.

`fllama` is different. It uses Dart's **native assets** hooks, which run for
*every* target — including the host when you run `flutter test`. Two
consequences, both measured here:

1. **It breaks `flutter test` on this machine.** The hook builds llama.cpp for
   macOS via `native_toolchain_cmake`, whose toolchain file is incompatible
   with CMake 4.x:

   ```
   CMake Error at native_toolchain_cmake-0.2.7/cmake/ios.toolchain.cmake:668
     get_filename_component called with incorrect number of arguments
   ```

   The *Android* build is fine, because Gradle uses the Android SDK's bundled
   CMake 3.22.1 rather than whatever is on your PATH. Only the host build
   picks up Homebrew's CMake 4.

2. **Even if it worked, it would compile llama.cpp for macOS on every clean
   checkout just to run pure-Dart unit tests.** Those tests cover number
   parsing and scoring. They have no business waiting on a 309-target C++
   build.

So the default is speech-on, LLM-off, and the LLM is switched on per build:

```bash
./scripts/enable_native_ai.sh              # both
./scripts/enable_native_ai.sh --asr-only   # speech only (the default state)
./scripts/disable_native_ai.sh             # back to rules only
```

Turn the LLM on when you are building for the device, and run
`--asr-only` (or `disable`) when you want the test suite back. If you need
both at once, install a CMake 3.x on the host and put it ahead of Homebrew's
on PATH.

### What was verified with the LLM enabled

- `fllama` resolves from git at the pinned commit
- `flutter analyze` clean
- `flutter build apk --release` succeeds; llama.cpp compiles (309 targets,
  ~2.5 min) and `libfllama.so` (10.5 MB) is registered as a native asset and
  lands in the APK
- The release APK still declares no `INTERNET` permission

Not verified: Gemma actually loading and generating. The model is 1.6 GB and
the one push attempted here was interrupted — which is how the truncated-model
bug below was found.

### The API does not match the docs you will find

`OpenAiRequest` has **no `grammar` field**. The GBNF-constrained decoding that
`native_ai/fllama_extractor.dart` was originally written against does not
exist; the API offers `tools`/`toolChoice` instead. The extractor now leans on
a blunt prompt, greedy decoding, brace-slicing, and `AiRuntime` repairing the
result from the deterministic extractor. `Message(Role.user, text)` and the
`fllamaChat(request, (response, json, done) {})` callback arity were both
checked and do match.

## If the Android build fails

Almost always NDK/ABI. In order:

1. **Check the ABI filter.** These libraries ship `arm64-v8a` and often nothing
   else. In `android/app/build.gradle`:
   ```groovy
   android {
       defaultConfig {
           ndk { abiFilters 'arm64-v8a' }
       }
   }
   ```
   The iQOO device is arm64, so dropping the other ABIs is free.

2. **Check the NDK version** matches what the plugin expects. Set it explicitly
   in `android/app/build.gradle` (`ndkVersion "26.1.10909125"` or whatever the
   plugin documents) rather than relying on the default.

3. **`minSdk`** must be at least 24. `scripts/configure_android.py` sets this,
   but `flutter create` will reset it if you re-run it.

4. **Clean between attempts** — stale native artefacts produce confusing
   errors:
   ```bash
   flutter clean && rm -rf android/.gradle && flutter pub get
   ```

5. If you are more than an hour in, run `disable_native_ai.sh` and move on.

## What "on-device" means here

llama.cpp on Android runs on **CPU**, and on GPU via Vulkan/OpenCL where a
backend is compiled in. It does **not** use the phone's NPU/Hexagon DSP. True
NPU delegation means Qualcomm's QNN SDK or a TFLite NPU delegate — a much
bigger integration than this build allows.

Say "on-device inference". Do not say "NPU accelerated". The claim is checkable
and the accurate version is impressive on its own.
