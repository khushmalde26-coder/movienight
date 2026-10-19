package com.khush.movienight.ui

import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** How the app is laid out: touch with a tab bar, touch with a side rail, or a TV driven by a remote. */
enum class FormFactor { PHONE, TABLET, TV }

val LocalFormFactor = staticCompositionLocalOf { FormFactor.PHONE }

/** Debug builds only: set from MainActivity to try another layout on any device. */
var formFactorOverride: FormFactor? = null

object Palette {
    val ink = Color(0xFF0B0B0F)
    val surface = Color(0xFF1C1C1E)
    val raised = Color(0xFF2C2C2E)
    val text = Color(0xFFF5F5F7)
    val muted = Color(0xFFA1A1A6)
    val accent = Color(0xFFE5E5EA)
    val focus = Color.White
}

/** Spacing and sizes, larger on a TV viewed from across the room. */
data class Metrics(val gutter: Dp, val cardWidth: Dp, val heroHeight: Dp, val rowSpacing: Dp)

val LocalMetrics = staticCompositionLocalOf { Metrics(16.dp, 200.dp, 420.dp, 28.dp) }

@Composable
fun MovieNightTheme(content: @Composable () -> Unit) {
    val context = LocalContext.current
    val configuration = LocalConfiguration.current
    val form = remember(configuration.screenWidthDp) {
        val uiMode = (context.getSystemService(Context.UI_MODE_SERVICE) as UiModeManager).currentModeType
        when {
            formFactorOverride != null -> formFactorOverride!!
            uiMode == Configuration.UI_MODE_TYPE_TELEVISION -> FormFactor.TV
            configuration.smallestScreenWidthDp >= 600 -> FormFactor.TABLET
            else -> FormFactor.PHONE
        }
    }
    val metrics = when (form) {
        FormFactor.PHONE -> Metrics(16.dp, 200.dp, 440.dp, 24.dp)
        FormFactor.TABLET -> Metrics(32.dp, 260.dp, 520.dp, 32.dp)
        // TV screens report about 960 × 540 dp; leave the overscan-safe margin on the sides.
        FormFactor.TV -> Metrics(48.dp, 240.dp, 400.dp, 28.dp)
    }
    val colors = darkColorScheme(
        primary = Palette.accent, onPrimary = Color.Black, background = Palette.ink, onBackground = Palette.text,
        surface = Palette.ink, onSurface = Palette.text, surfaceVariant = Palette.surface, onSurfaceVariant = Palette.muted,
        surfaceContainer = Palette.surface, surfaceContainerHigh = Palette.raised, secondaryContainer = Palette.raised,
        onSecondaryContainer = Palette.text,
    )
    CompositionLocalProvider(LocalFormFactor provides form, LocalMetrics provides metrics) {
        MaterialTheme(colorScheme = colors, content = content)
    }
}
