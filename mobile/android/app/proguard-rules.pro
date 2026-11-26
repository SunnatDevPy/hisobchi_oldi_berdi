# Keep Flutter engine and plugin reflection entrypoints
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class com.google.firebase.** { *; }
-dontwarn io.flutter.embedding.**

# AndroidX BiometricPrompt & FileProvider
-keep class androidx.biometric.** { *; }
-keep class androidx.core.content.FileProvider { *; }

# Keep MainActivity & generated BuildConfig
-keep class uz.hisobchi.hisobchi_app.MainActivity { *; }
-keep class uz.hisobchi.hisobchi_app.BuildConfig { *; }
