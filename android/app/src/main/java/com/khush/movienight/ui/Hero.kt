package com.khush.movienight.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.khush.movienight.core.ContentKind
import com.khush.movienight.data.MediaItem

/** Date · length · quality, as on a streaming service's title page. */
@Composable
fun MetadataLine(item: MediaItem) {
    val length = Formatters.remaining(item.remainingSeconds) ?: Formatters.duration(item.duration)
    val whenText = when (item.contentKind) {
        ContentKind.HOME_VIDEO -> Formatters.date(item.bestDate)
        ContentKind.EPISODE -> item.episodeLabel
        ContentKind.FILM, ContentKind.EXTRA -> item.year?.toString()
    }
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(listOfNotNull(whenText, length).joinToString("  ·  "), style = MaterialTheme.typography.bodyMedium, color = Palette.muted)
        Formatters.badge(item.width, item.height)?.let { Chip(it) }
    }
}

/**
 * The big artwork banner at the top of a page with Play, Start Over and More Info.
 * On a TV the Play button takes focus first, so OK on the remote plays straight away.
 */
@Composable
fun Hero(
    item: MediaItem,
    navigator: Navigator,
    showsMoreInfo: Boolean = true,
    eyebrow: String? = item.collection.ifEmpty { null },
    onBack: (() -> Unit)? = null,
    takeFocus: Boolean = false,
) {
    val app = rememberApp()
    val metrics = LocalMetrics.current
    val startFromBeginning by app.preferences.startFromBeginning.collectAsState()
    val offline by app.store.offline.collectAsState()
    val available = item.sourceId !in offline
    val resume = item.resumePosition(startFromBeginning)
    val playFocus = remember { FocusRequester() }
    if (takeFocus) InitialFocus(playFocus, item.key)
    Box(Modifier.fillMaxWidth().height(metrics.heroHeight)) {
        // On TV the tabs float over the banner, so the artwork runs to the top of the screen.
        Artwork(item, Modifier.fillMaxSize(), cornerRadius = 0.dp)
        // Fade the artwork into the page, and darken the side the text sits on.
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.35f to Color.Transparent, 1f to Palette.ink)))
        Box(Modifier.fillMaxSize().background(Brush.horizontalGradient(0f to Palette.ink.copy(alpha = 0.7f), 0.6f to Color.Transparent)))
        if (onBack != null && LocalFormFactor.current != FormFactor.TV) {
            IconButton(onBack, Modifier.padding(top = 36.dp, start = 8.dp)) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back", tint = Color.White) }
        }
        Column(
            Modifier.align(Alignment.BottomStart).padding(horizontal = metrics.gutter, vertical = 20.dp).widthIn(max = 720.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            eyebrow?.let { Text(it.uppercase(), style = MaterialTheme.typography.labelMedium, color = Palette.muted, fontWeight = FontWeight.SemiBold) }
            Text(item.displayTitle, style = MaterialTheme.typography.displaySmall, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis)
            MetadataLine(item)
            if (!available) Text("The drive or folder this video is on isn't connected.", color = Color(0xFFFFB340), style = MaterialTheme.typography.bodyMedium)
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                ActionButton(if (resume != null) "Resume" else "Play", Icons.Default.PlayArrow, { navigator.play(item) },
                    Modifier.focusRequester(playFocus), primary = true, enabled = available)
                // Smart resume: continuing is the big button, starting over is right beside it.
                if (resume != null) ActionButton("Start Over", Icons.Default.Replay, { navigator.play(item, 0.0) }, enabled = available)
                if (showsMoreInfo) ActionButton("More Info", Icons.Outlined.Info, { navigator.open(item) })
            }
        }
    }
}
