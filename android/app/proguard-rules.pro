# ProGuard rules for GearUp Android
# Keep Google Sign-In classes from being obfuscated

# Google Sign-In
-keep class com.google.android.gms.auth.** { *; }
-keep class com.google.android.gms.common.** { *; }
-keep class com.google.android.gms.signin.** { *; }
-keep class com.google.android.gms.tasks.** { *; }

# Firebase Auth
-keep class com.google.firebase.auth.** { *; }
-keep class com.google.firebase.** { *; }

# Keep google-services
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Keep annotations
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes Exceptions

# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# --- KEEP RULES FOR PLAY ASSET DELIVERY (SplitInstall) ---
-keep class com.google.android.play.core.splitcompat.** { *; }
-keep class com.google.android.play.core.splitinstall.** { *; }
-keep class com.google.android.play.core.tasks.** { *; }
-keep class com.google.android.play.core.common.** { *; }
-keep class io.flutter.embedding.engine.deferredcomponents.** { *; }
-keepclassmembers class * {
    @androidx.annotation.Keep *;
}
-dontwarn com.google.android.play.core.**
