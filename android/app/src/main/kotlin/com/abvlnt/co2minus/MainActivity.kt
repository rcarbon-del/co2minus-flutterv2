package com.abvlnt.co2minus

import android.content.Intent
import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "co2minus.app/ar_depth"
    private var pendingResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // This tells Android to draw the app behind the system bars (status and nav bar)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "measureDepth") {
                pendingResult = result
                // Launch the Native AR Window
                val intent = Intent(this, ArDepthActivity::class.java)
                startActivityForResult(intent, 1001)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 1001) {
            if (resultCode == RESULT_OK) {
                // Return depth in centimeters back to Flutter
                val depthCm = data?.getDoubleExtra("DEPTH_CM", 30.0)
                pendingResult?.success(depthCm)
            } else {
                pendingResult?.success(null) // User aborted
            }
            pendingResult = null
        }
    }
}