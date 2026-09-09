# KhataSetu R8/ProGuard rules.
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
