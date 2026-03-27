# ML Kit Text Recognition
-dontwarn com.google.mlkit.vision.text.**
-keep class com.google.mlkit.vision.text.** { *; }

# TensorFlow Lite
-dontwarn org.tensorflow.lite.gpu.**
-keep class org.tensorflow.lite.** { *; }

# Google Play Services ML
-keep class com.google.android.gms.internal.ml.** { *; }
-dontwarn com.google.android.gms.internal.ml.**

# Ignore missing optional ML Kit libraries
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
