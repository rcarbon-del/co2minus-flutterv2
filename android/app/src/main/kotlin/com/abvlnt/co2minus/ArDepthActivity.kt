package com.abvlnt.co2minus

import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.google.ar.sceneform.ux.ArFragment

class ArDepthActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 1. Create the AR Fragment (Handles camera, permissions, and session automatically)
        val arFragment = ArFragment()

        // Put the AR View on the full screen
        supportFragmentManager.beginTransaction()
            .replace(android.R.id.content, arFragment)
            .commit()

        // Force the UI transaction to execute immediately
        supportFragmentManager.executePendingTransactions()

        // 2. Listen for the user tapping on the real-world object
        arFragment.setOnTapArPlaneListener { hitResult, plane, motionEvent ->

            // ARCore provides the exact physical distance from the lens to the object in meters
            val distanceInMeters = hitResult.distance
            val distanceInCm = distanceInMeters * 100.0

            // 3. Send data back to the Flutter pipeline
            val resultIntent = Intent()
            resultIntent.putExtra("DEPTH_CM", distanceInCm.toDouble())
            setResult(RESULT_OK, resultIntent)

            // 4. Close the AR Window
            finish()
        }

        Toast.makeText(this, "AR Active: Scan area, then tap the item to measure depth!", Toast.LENGTH_LONG).show()
    }
}