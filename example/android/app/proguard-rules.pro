# Rules for the example's camera MRZ scanner (google_mlkit_text_recognition).
# biometric_passport_nfc ships its own NFC rules via consumer-rules.pro.

# The ML Kit Flutter plugin references the Chinese, Devanagari, Japanese and Korean
# recognizers, but only the Latin model is bundled (MRZ text is Latin).
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# ML Kit instantiates its Firebase ComponentRegistrar classes reflectively. Under R8 full
# mode the library's bare -keep doesn't retain their no-arg constructors, so component
# registration silently fails and InputImage.fromByteArray throws an NPE in release.
-keep class * implements com.google.firebase.components.ComponentRegistrar { <init>(); }
