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

        val container = FrameLayout(this)
        container.id = View.generateViewId()
        setContentView(container)

        val arFragment = ArFragment()

        // WAIT for the fragment UI to exist before attaching lasers
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

        Handler(Looper.getMainLooper()).postDelayed({
            if (!depthFound) {
                depthFound = true
                val resultIntent = Intent()
                resultIntent.putExtra("DEPTH_CM", 30.0)
                setResult(RESULT_OK, resultIntent)
                finish()
            }
        }, 10000)
    }

    private fun setupArUpdateListener(arFragment: ArFragment) {
        val sceneView = arFragment.arSceneView ?: return

        sceneView.scene.addOnUpdateListener {
            if (depthFound) return@addOnUpdateListener

            val frame = sceneView.arFrame ?: return@addOnUpdateListener
            if (frame.camera.trackingState != TrackingState.TRACKING) return@addOnUpdateListener

            val centerX = sceneView.width / 2f
            val centerY = sceneView.height / 2f

            val hitResults = frame.hitTest(centerX, centerY)
            for (hit in hitResults) {
                val distanceInCm = hit.distance * 100.0
                if (distanceInCm > 0 && distanceInCm < 300.0) {
                    depthFound = true
                    val resultIntent = Intent()
                    resultIntent.putExtra("DEPTH_CM", distanceInCm.toDouble())
                    setResult(RESULT_OK, resultIntent)
                    finish()
                    break
                }
            }
        }
    }
}