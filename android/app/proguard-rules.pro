# KhataSetu R8/ProGuard rules.
#
# google_mlkit_text_recognition's Java code references every script
# recogniser (Latin, Chinese, Japanese, Korean, Devanagari), but we depend on
# only the Devanagari artefact to keep the APK small. R8 then fails the
# release build on the classes that are not there.
#
# Suppressing the warnings is correct rather than a workaround: those code
# paths are unreachable because the app never asks for those scripts. The
# alternative is shipping four more recognition models we will never load.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
-dontwarn com.google.mlkit.vision.text.devanagari.**

# Keep the ML Kit entry points the plugin reflects over.
-keep class com.google.mlkit.** { *; }
