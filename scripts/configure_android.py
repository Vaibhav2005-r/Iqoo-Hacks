#!/usr/bin/env python3
"""Applies KhataSetu's Android configuration to freshly generated scaffolding.

Idempotent: safe to re-run after any `flutter create`.

Two things matter here beyond the usual permissions:

  * minSdk 24 - ML Kit text recognition needs 21, and the llama.cpp / whisper
    native builds want 24.
  * INTERNET is NOT declared. Flutter injects it into the debug and profile
    manifests for hot reload, but a release build of this app has no network
    permission at all. That turns "your data never leaves the phone" from a
    claim into something a judge can verify with `aapt dump permissions`.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

PERMISSIONS = [
    ("android.permission.RECORD_AUDIO", "voice khata entry"),
    ("android.permission.CAMERA", "photographing a khata page"),
    ("android.permission.READ_MEDIA_IMAGES", "choosing a page from the gallery (API 33+)"),
]

LEGACY_STORAGE = (
    '    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"\n'
    '        android:maxSdkVersion="32" />\n'
)


def patch_manifest() -> bool:
    path = ROOT / "android/app/src/main/AndroidManifest.xml"
    if not path.exists():
        print(f"  ! {path} not found - run flutter create first")
        return False

    text = path.read_text()
    if "RECORD_AUDIO" in text:
        print("  = manifest already configured")
        return True

    block = ["\n    <!-- KhataSetu: capture permissions. -->\n"]
    for name, why in PERMISSIONS:
        block.append(f'    <!-- {why} -->\n')
        block.append(f'    <uses-permission android:name="{name}" />\n')
    block.append(LEGACY_STORAGE)
    block.append(
        "\n    <!-- No INTERNET permission by design: the core product runs\n"
        "         entirely on-device. Flutter adds it to debug/profile builds\n"
        "         for hot reload only. -->\n"
    )

    text = text.replace("<application", "".join(block) + "\n    <application", 1)
    path.write_text(text)
    print("  + manifest permissions added")
    return True


def patch_gradle() -> bool:
    """Raise minSdk. Handles both the Groovy and Kotlin DSL layouts."""
    candidates = [
        ROOT / "android/app/build.gradle",
        ROOT / "android/app/build.gradle.kts",
    ]
    path = next((p for p in candidates if p.exists()), None)
    if path is None:
        print("  ! android/app/build.gradle not found")
        return False

    text = path.read_text()
    original = text

    # Newer templates use `minSdk = flutter.minSdkVersion`; older ones use
    # `minSdkVersion flutter.minSdkVersion`.
    text = re.sub(r"minSdk(?:Version)?\s*=\s*[^\n]+", "minSdk = 24", text)
    text = re.sub(r"minSdkVersion\s+[^\n=]+", "minSdkVersion 24", text)

    if text == original:
        print("  = gradle minSdk already set or pattern not found")
        return True

    path.write_text(text)
    print(f"  + minSdk raised to 24 in {path.name}")
    return True


PROGUARD_RULES = """# KhataSetu R8/ProGuard rules.
#
# google_mlkit_text_recognition's Java code references every script recogniser,
# but the plugin bundles only Latin and this app additionally declares
# Devanagari (see build.gradle.kts). Chinese, Japanese and Korean are genuinely
# absent, and R8 fails the release build on them.
#
# Suppressing those three is correct: the app never asks for those scripts, so
# the code paths are unreachable, and the alternative is shipping three
# recognition models it will never load.
#
# Devanagari is deliberately NOT in this list. It is a real dependency, and
# silencing it here is what hid a NoClassDefFoundError that crashed the scan
# flow at runtime while the build stayed green.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Keep the ML Kit entry points the plugin reflects over.
-keep class com.google.mlkit.** { *; }
"""


def patch_proguard() -> bool:
    """Write the R8 rules file and reference it from the release build type."""
    rules = ROOT / "android/app/proguard-rules.pro"
    if not rules.parent.exists():
        print("  ! android/app not found")
        return False

    if not rules.exists() or "mlkit" not in rules.read_text():
        rules.write_text(PROGUARD_RULES)
        print("  + proguard-rules.pro written")
    else:
        print("  = proguard-rules.pro already present")

    candidates = [
        ROOT / "android/app/build.gradle.kts",
        ROOT / "android/app/build.gradle",
    ]
    path = next((p for p in candidates if p.exists()), None)
    if path is None:
        print("  ! app build file not found")
        return False

    text = path.read_text()
    if "proguard-rules.pro" in text:
        print("  = release build type already references the rules")
        return True

    if path.suffix == ".kts":
        anchor = 'signingConfig = signingConfigs.getByName("debug")'
        addition = (
            anchor
            + "\n            proguardFiles(\n"
            '                getDefaultProguardFile("proguard-android-optimize.txt"),\n'
            '                "proguard-rules.pro",\n'
            "            )"
        )
    else:
        anchor = "signingConfig signingConfigs.debug"
        addition = (
            anchor
            + "\n            proguardFiles "
            "getDefaultProguardFile('proguard-android-optimize.txt'), "
            "'proguard-rules.pro'"
        )

    if anchor not in text:
        print("  ! could not find the release signingConfig line to anchor to")
        return False

    path.write_text(text.replace(anchor, addition, 1))
    print(f"  + release build type now uses proguard-rules.pro ({path.name})")
    return True


RELEASE_MANIFEST = """<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <!-- Release-only manifest overlay.

         ML Kit pulls in com.google.android.datatransport:transport-backend-cct
         transitively, and that component declares INTERNET and
         ACCESS_NETWORK_STATE so it can upload usage telemetry to Google. We
         never ask for a network, and a ledger app for shopkeepers should not
         ship a telemetry uploader, so both permissions are stripped from the
         release build.

         The Devanagari text recogniser is the BUNDLED artefact, so OCR reads
         a model shipped inside the APK and needs no network at any point.

         This overlay is release-only on purpose: Flutter injects INTERNET into
         the debug manifest for hot reload, and removing it there would break
         `flutter run`. -->
    <uses-permission android:name="android.permission.INTERNET"
        tools:node="remove" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"
        tools:node="remove" />
</manifest>
"""


def patch_release_manifest() -> bool:
    """Strip network permissions from release builds.

    Turns "nothing leaves your phone" from a claim into something checkable
    with `aapt dump permissions`.
    """
    path = ROOT / "android/app/src/release/AndroidManifest.xml"
    if not (ROOT / "android/app/src").exists():
        print("  ! android/app/src not found")
        return False

    if path.exists() and "tools:node" in path.read_text():
        print("  = release manifest overlay already present")
        return True

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(RELEASE_MANIFEST)
    print("  + release manifest strips INTERNET / ACCESS_NETWORK_STATE")
    return True


MLKIT_DEPENDENCIES = """
dependencies {
    // The google_mlkit_text_recognition plugin bundles ONLY the Latin
    // recogniser. Every other script is an opt-in artefact that the app must
    // declare itself, and asking for one that is absent is not a build error —
    // it is a NoClassDefFoundError the moment a scan is attempted.
    //
    // KhataSetu reads Hindi khata pages, so it needs Devanagari. This line is
    // the difference between the scan flow working and the app crashing to the
    // launcher.
    implementation("com.google.mlkit:text-recognition-devanagari:16.0.1")
}
"""


def patch_mlkit_dependency() -> bool:
    """Add the Devanagari recogniser artefact, which the plugin does not."""
    candidates = [
        ROOT / "android/app/build.gradle.kts",
        ROOT / "android/app/build.gradle",
    ]
    path = next((p for p in candidates if p.exists()), None)
    if path is None:
        print("  ! app build file not found")
        return False

    text = path.read_text()
    if "text-recognition-devanagari" in text:
        print("  = ML Kit Devanagari dependency already present")
        return True

    if path.suffix == ".kts":
        addition = MLKIT_DEPENDENCIES
    else:
        addition = MLKIT_DEPENDENCIES.replace(
            'implementation("com.google.mlkit:text-recognition-devanagari:16.0.1")',
            "implementation 'com.google.mlkit:text-recognition-devanagari:16.0.1'",
        )

    anchor = "flutter {"
    if anchor not in text:
        print("  ! could not find the flutter block to anchor to")
        return False

    path.write_text(text.replace(anchor, addition.strip() + "\n\n" + anchor, 1))
    print(f"  + ML Kit Devanagari recogniser added to {path.name}")
    return True


def patch_app_label() -> bool:
    """Set the launcher label.

    flutter create derives it from the project name, so it shows as
    "khatasetu" in the launcher and in system permission dialogs.
    """
    path = ROOT / "android/app/src/main/AndroidManifest.xml"
    if not path.exists():
        print("  ! manifest not found")
        return False

    text = path.read_text()
    if 'android:label="KhataSetu"' in text:
        print("  = app label already set")
        return True

    updated = re.sub(r'android:label="[^"]*"', 'android:label="KhataSetu"', text, count=1)
    if updated == text:
        print("  ! no android:label attribute found")
        return False

    path.write_text(updated)
    print("  + app label set to KhataSetu")
    return True


def main() -> int:
    print("Configuring Android project...")
    ok = patch_manifest()
    ok = patch_gradle() and ok
    ok = patch_proguard() and ok
    ok = patch_release_manifest() and ok
    ok = patch_mlkit_dependency() and ok
    ok = patch_app_label() and ok
    if not ok:
        print("\nSome steps did not apply. See docs/ANDROID.md to do them by hand.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
