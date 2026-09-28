# SQLCipher ProGuard / R8 Obfuscation Rules
-keep class net.sqlcipher.** { *; }
-keep class net.sqlcipher.database.** { *; }

# ML Kit Text Recognition Optional Scripts
-dontwarn com.google.mlkit.vision.text.**
