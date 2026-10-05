# Consumer R8/ProGuard rules for biometric_passport_nfc, merged into the app build.

# SCUBA (Smart Card abstraction & Android IsoDepCardService)
-keep class net.sf.scuba.** { *; }
-keepclassmembers class net.sf.scuba.** { *; }
-dontwarn net.sf.scuba.**

# JMRTD (ICAO 9303 ePassport protocol & Data Groups)
-keep class org.jmrtd.** { *; }
-keepclassmembers class org.jmrtd.** { *; }
-dontwarn org.jmrtd.**

# BouncyCastle crypto provider (used directly by JMRTD)
-keep class org.bouncycastle.** { *; }
-keepclassmembers class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**

# SpongyCastle crypto provider
-keep class org.spongycastle.** { *; }
-keepclassmembers class org.spongycastle.** { *; }
-dontwarn org.spongycastle.**

# Android NFC IsoDep
-keep class android.nfc.tech.IsoDep { *; }
-keepclassmembers class android.nfc.tech.IsoDep { *; }

# Apache Commons IO
-keep class org.apache.commons.io.** { *; }
-dontwarn org.apache.commons.io.**

# Retain all reflection-instantiated CardService and LDS classes
-keep class * extends net.sf.scuba.smartcards.CardService {
    public <init>(...);
    public static ** getInstance(...);
}

-keep class * extends org.jmrtd.lds.AbstractLDSFile {
    public <init>(...);
}

-keep class * extends org.jmrtd.lds.SecurityInfo {
    public <init>(...);
    public static ** getInstance(...);
}

# Preserve attributes needed for reflection and cryptography
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
