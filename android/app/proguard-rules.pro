
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

-dontwarn com.google.android.play.core.**

-keepattributes Signature
-keepattributes *Annotation*

-dontwarn com.google.mlkit.vision.text.**
-keep class com.google.mlkit.vision.text.** { *; }

-keep class com.google.android.gms.internal.ml.** { *; }
-dontwarn com.google.android.gms.internal.ml.**

-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

-keep class org.tensorflow.lite.** { *; }
-keep class org.tensorflow.** { *; }
-keep class com.ultralytics.** { *; }
-dontwarn org.tensorflow.lite.gpu.**
-dontwarn org.tensorflow.**

-dontwarn java.beans.**
-dontwarn org.yaml.snakeyaml.**