# Flutter & AndroidX keep rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keepclassmembers class * {
    @androidx.annotation.Keep *;
}

# Play Store Deferred Components (optional, not bundled in standalone APK)
-dontwarn com.google.android.play.core.**

# Firebase Realtime Database & Auth models
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn javax.annotation.**
-dontwarn org.jetbrains.annotations.**
