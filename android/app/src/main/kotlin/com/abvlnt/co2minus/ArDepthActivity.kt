package com.abvlnt.co2minus

import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.FrameLayout
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.fragment.app.Fragment
import androidx.fragment.app.FragmentManager
import com.google.ar.core.TrackingState
import com.google.ar.sceneform.ux.ArFragment

class ArDepthActivity : AppCompatActivity() {
    private var depthFound = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 1. Create a dedicated container for the AR Fragment
        val container = FrameLayout(this)
        container.id = View.generateViewId()
        setContentView(container)

        val arFragment = ArFragment()

        // 2. CRITICAL FIX: Wait for the fragment to actually build its UI before accessing it!
        supportFragmentManager.registerFragmentLifecycleCallbacks(object : FragmentManager.FragmentLifecycleCallbacks() {
            override fun onFragmentViewCreated(fm: FragmentManager, f: Fragment, v: View, savedInstanceState: Bundle?) {
                super.onFragmentViewCreated(fm, f, v, savedInstanceState)
                if (f === arFragment) {
                    setupArUpdateListener(f as ArFragment)
                }
            }
        }, false)

        supportFragmentManager.beginTransaction()
            .replace(container.id, arFragment)
            .commit()

        Toast.makeText(this, "Measuring True Depth...", Toast.LENGTH_LONG).show()

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

    private fun setupArUpdateListener(arFragment: ArFragment) {
        val sceneView = arFragment.arSceneView ?: return

        // 4. AUTOMATED RAYCAST (HitTest) - Fires 60 times a second!
        sceneView.scene.addOnUpdateListener {
            if (depthFound) return@addOnUpdateListener

            val frame = sceneView.arFrame ?: return@addOnUpdateListener
            if (frame.camera.trackingState != TrackingState.TRACKING) return@addOnUpdateListener

            // Get exact center of screen
            val centerX = sceneView.width / 2f
            val centerY = sceneView.height / 2f

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
    }
}