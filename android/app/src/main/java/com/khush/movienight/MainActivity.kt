package com.khush.movienight

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.khush.movienight.ui.FormFactor
import com.khush.movienight.ui.MovieNightRoot
import com.khush.movienight.ui.debugPlay
import com.khush.movienight.ui.formFactorOverride
import com.khush.movienight.ui.MovieNightTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Debug builds: "--es formFactor tv" (or tablet, phone) tries another layout on any device; it is remembered, and "auto" clears it.
        if (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            val debug = getSharedPreferences("debug", MODE_PRIVATE)
            intent.getStringExtra("formFactor")?.let { debug.edit().putString("formFactor", it).commit() }
            formFactorOverride = FormFactor.entries.firstOrNull { it.name.equals(debug.getString("formFactor", null), true) }
            // "--es play <part of a file name>" opens the player on that video, for checking playback.
            debugPlay = intent.getStringExtra("play")
        }
        enableEdgeToEdge(statusBarStyle = SystemBarStyle.dark(0), navigationBarStyle = SystemBarStyle.dark(0))
        setContent {
            MovieNightTheme { MovieNightRoot() }
        }
    }

    override fun onStart() {
        super.onStart()
        // Drives may have been plugged in or out while the app was away.
        (application as MovieNightApp).store.refreshAvailability()
    }
}
