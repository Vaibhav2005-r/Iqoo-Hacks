# Android configuration

`android/` **is committed**, and it is the exact project that was verified to
build. `scripts/configure_android.py` applies every change below and is
idempotent, so it can be re-run at any time — and `scripts/setup.sh` runs it
automatically after regenerating the platform folders.

Regenerate only if `android/` is missing or you have broken it:

```bash
./scripts/setup.sh
```

Everything here was found by actually building an APK. None of it is visible
from the Dart source.

## 1. Permissions — `android/app/src/main/AndroidManifest.xml`

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
    android:maxSdkVersion="32" />
```

`record` requests the microphone permission itself and `image_picker` handles
the camera, so the app declares no runtime-permission plugin of its own.

## 2. `minSdk 24` — `android/app/build.gradle.kts`

ML Kit text recognition needs 21; the llama.cpp and whisper.cpp native builds
want 24. Note `flutter create` resets this, which is why the configure script
reapplies it.

## 3. R8 keep rules — `android/app/proguard-rules.pro`

Release builds fail without these:

```
Missing class com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
```

`google_mlkit_text_recognition`'s Java code references every script recogniser
(Latin, Chinese, Japanese, Korean, Devanagari), but the project depends only on
the Devanagari artefact. R8 then fails on the classes that are not there.
`-dontwarn` is the correct answer rather than a workaround: those code paths
are unreachable because the app never asks for those scripts, and the
alternative is shipping four recognition models it will never load.

Debug builds do not minify, so this only ever bites on release — the build you
make last, under time pressure.

## 4. Stripping network access — `android/app/src/release/AndroidManifest.xml`

ML Kit pulls in `com.google.android.datatransport:transport-backend-cct`
transitively. That is Google's telemetry uploader, and its manifest contributes
`INTERNET` and `ACCESS_NETWORK_STATE` to the merged manifest. Left alone, the
release APK ships with network access and a component that wants to phone home
— against the whole point of the product.

The release overlay removes both:

```xml
<uses-permission android:name="android.permission.INTERNET"
    tools:node="remove" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"
    tools:node="remove" />
```

Release only. Flutter injects `INTERNET` into the debug manifest for hot
reload; removing it there breaks `flutter run`.

**Verify after any dependency change:**

```bash
$ANDROID_HOME/build-tools/36.0.0/aapt2 dump permissions \
  build/app/outputs/flutter-apk/app-release.apk
```

Expected: RECORD_AUDIO, CAMERA, READ_MEDIA_IMAGES, READ_EXTERNAL_STORAGE, and
nothing else. A new dependency can quietly reintroduce `INTERNET`.

**And smoke-test a scan on the device afterwards.** OCR uses the *bundled*
Devanagari model, so it needs no network — but a permission strip is exactly
the kind of change that no static check will catch if that assumption is ever
wrong.

## Which manifest wins

| Variant | INTERNET | Why |
|---|---|---|
| debug | yes | Flutter injects it for hot reload |
| profile | yes | same |
| release | **no** | stripped by the release overlay |

## APK size

The release APK is ~84 MB, dominated by the bundled ML Kit Devanagari model —
the cost of OCR that works with no network. To cut it for a device install:

```bash
flutter build apk --release --split-per-abi
```

The `arm64-v8a` APK is the only one the demo phone needs.

## Toolchain this was verified against

Flutter 3.47.2 · Dart 3.13.2 · Android SDK 36.0.0 · build-tools 36.0.0 ·
Gradle 9.3.1 · JDK 25.
