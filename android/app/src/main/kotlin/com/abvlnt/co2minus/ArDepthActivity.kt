package com.abvlnt.co2minus

import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.google.ar.sceneform.ux.ArFragment
import com.google.ar.core.TrackingState

class ArDepthActivity : AppCompatActivity() {
    private var depthFound = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 1. Create the AR Fragment
        val arFragment = ArFragment()
        supportFragmentManager.beginTransaction()
            .replace(android.R.id.content, arFragment)
            .commit()
        supportFragmentManager.executePendingTransactions()

        // (The planeDiscoveryController lines were removed from here!)

        Toast.makeText(this, "Measuring True Depth...", Toast.LENGTH_LONG).show()

        // 2. AUTOMATED RAYCAST (HitTest) - Fires 60 times a second!
        arFragment.arSceneView.scene.addOnUpdateListener {
            if (depthFound) return@addOnUpdateListener

            val frame = arFragment.arSceneView.arFrame ?: return@addOnUpdateListener
            if (frame.camera.trackingState != TrackingState.TRACKING) return@addOnUpdateListener

            // Get exact center of screen
            val centerX = arFragment.arSceneView.width / 2f
            val centerY = arFragment.arSceneView.height / 2f

            // Fire laser
            val hitResults = frame.hitTest(centerX, centerY)
            for (hit in hitResults) {
                val distanceInCm = hit.distance * 100.0

                // If laser hits a surface within 3 meters...
                if (distanceInCm > 0 && distanceInCm < 300.0) {
                    depthFound = true

                    val resultIntent = Intent()
                    resultIntent.putExtra("DEPTH_CM", distanceInCm.toDouble())
                    setResult(RESULT_OK, resultIntent)
                    finish() // Instantly close AR and return to Flutter!
                    break
                }
            }
        }

        // 3. Failsafe Timeout (10 seconds)
        Handler(Looper.getMainLooper()).postDelayed({
            if (!depthFound) {
                depthFound = true
                val resultIntent = Intent()
                resultIntent.putExtra("DEPTH_CM", 30.0) // Fallback baseline distance
                setResult(RESULT_OK, resultIntent)
                finish()
            }
        }, 10000)
    }
}