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


def main() -> int:
    print("Configuring Android project...")
    ok = patch_manifest()
    ok = patch_gradle() and ok
    if not ok:
        print("\nSome steps did not apply. See docs/ANDROID.md to do them by hand.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
