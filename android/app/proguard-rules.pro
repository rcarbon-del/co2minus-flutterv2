#ML Kit Text Recognition
-dontwarn com.google.mlkit.vision.text.**
-keep class com.google.mlkit.vision.text.** { *; }

#Google Play Services ML
-keep class com.google.android.gms.internal.ml.** { ; }
-dontwarn com.google.android.gms.internal.ml.*

#Ignore missing optional ML Kit libraries
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

#Ultralytics
-keep class com.ultralytics.** { *; }

#TensorFlow Lite / flutter_litert
-dontwarn org.tensorflow.**
-dontwarn org.tensorflow.lite.gpu.**
-keep class org.tensorflow.** { *; }
-keep class org.tensorflow.lite.* { *; }

#Added for flutter_litert (prevents stripping JNI methods and buffer classes)
-keepclassmembers class org.tensorflow.lite.** { *; }
-keep class org.tensorflow.lite.flex.* { *; }
-keep class java.nio.* { *; }