package com.khush.movienight.playback

import android.app.Activity
import android.view.View
import androidx.activity.compose.BackHandler
import androidx.annotation.OptIn
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.net.toUri
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.mediacodec.MediaCodecDecoderException
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.mediacodec.MediaCodecUtil
import androidx.media3.ui.PlayerView
import com.khush.movienight.core.ContentKind
import com.khush.movienight.core.TVLibrary
import androidx.compose.foundation.layout.Row
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.GraphicEq
import com.khush.movienight.ui.ActionButton
import com.khush.movienight.ui.Navigator
import com.khush.movienight.ui.SoundControls
import com.khush.movienight.ui.isActive
import com.khush.movienight.ui.Palette
import com.khush.movienight.ui.rememberApp
import kotlinx.coroutines.delay
import androidx.media3.common.MediaItem as PlayerItem

/**
 * Full-screen playback with Media3 ExoPlayer: MP4, MKV, WebM, MPEG-TS and most codecs the device can
 * decode. Picks up where you left off, saves your place every few seconds, and goes on to the next
 * episode when one ends. The remote's D-pad and media keys work through the player's own controls.
 */
@OptIn(UnstableApi::class)
@Composable
fun PlayerScreen(key: String, start: Double?, navigator: Navigator) {
    val app = rememberApp()
    val context = LocalContext.current
    val items by app.store.items.collectAsState()
    val startFromBeginning by app.preferences.startFromBeginning.collectAsState()
    // Read once: the item updates as progress is saved, which mustn't restart playback.
    val item = remember(key, items == null) { items?.firstOrNull { it.key == key } } ?: return
    var error by remember { mutableStateOf<String?>(null) }
    var controlsVisible by remember { mutableStateOf(true) }
    var showSound by remember { mutableStateOf(false) }
    val sound by app.preferences.sound.collectAsState()
    // Decoders that failed on this video. Some devices' hardware decoders give up mid-file (and the
    // emulator's do on plain H.264), so playback carries on from the same spot with the next one.
    var failedDecoders by remember(key) { mutableStateOf(emptySet<String>()) }
    var restartAt by remember(key) { mutableStateOf<Double?>(null) }

    val player = remember(key, failedDecoders) {
        val selector = MediaCodecSelector { mimeType, secure, tunneling ->
            MediaCodecUtil.getDecoderInfos(mimeType, secure, tunneling).filter { it.name !in failedDecoders }
        }
        ExoPlayer.Builder(context, SoundRenderersFactory(context) { app.preferences.sound.value }.setEnableDecoderFallback(true)
            .setMediaCodecSelector(selector)
            // FFmpeg decodes the surround formats (AC-3, E-AC-3, DTS, TrueHD) the device can't.
            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON))
            .setAudioAttributes(AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(), true)
            .setHandleAudioBecomingNoisy(true)
            .build()
    }

    fun save() {
        val position = player.currentPosition / 1000.0
        val duration = player.duration.takeIf { it != C.TIME_UNSET }?.div(1000.0)
        if (position > 0) app.store.saveProgress(item.key, position, duration)
    }

    /** The episode after this one in the same show, if there is one. */
    fun nextEpisode() = items.orEmpty().takeIf { item.contentKind == ContentKind.EPISODE }?.let { all ->
        val show = TVLibrary.shows(all.map { it.browseEntry() }).firstOrNull { it.name == item.showName } ?: return@let null
        val index = show.episodeKeys.indexOf(item.key)
        show.episodeKeys.getOrNull(index + 1)?.let { next -> all.firstOrNull { it.key == next } }
    }

    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_ENDED) {
                    app.store.finish(item.key)
                    val next = nextEpisode()
                    navigator.back()
                    if (next != null) navigator.play(next, 0.0)
                }
            }

            override fun onPlayerError(e: PlaybackException) {
                val decoder = generateSequence(e.cause) { it.cause }.filterIsInstance<MediaCodecDecoderException>().firstOrNull()?.codecInfo?.name
                if (decoder != null && decoder !in failedDecoders) {
                    restartAt = player.currentPosition / 1000.0
                    failedDecoders = failedDecoders + decoder
                    return
                }
                error = "This video couldn't be played on this device (${e.errorCodeName}). It may use a format the device can't decode."
            }
        }
        player.addListener(listener)
        player.setMediaItem(PlayerItem.fromUri(item.uri.toUri()))
        val resume = restartAt ?: start ?: item.resumePosition(startFromBeginning)
        if (resume != null && resume > 0) player.seekTo((resume * 1000).toLong())
        player.prepare()
        player.playWhenReady = true
        onDispose {
            save()
            player.removeListener(listener)
            player.release()
        }
    }

    // Save your place every five seconds while playing.
    LaunchedEffect(player) {
        while (true) {
            delay(5_000)
            if (player.isPlaying) save()
        }
    }

    // Full screen: hide the status and navigation bars while watching.
    val view = LocalView.current
    DisposableEffect(view) {
        val window = (view.context as? Activity)?.window
        val controller = window?.let { WindowCompat.getInsetsController(it, view) }
        controller?.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        controller?.hide(WindowInsetsCompat.Type.systemBars())
        onDispose { controller?.show(WindowInsetsCompat.Type.systemBars()) }
    }

    BackHandler { navigator.back() }

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        AndroidView(
            factory = { viewContext ->
                PlayerView(viewContext).apply {
                    this.player = player
                    keepScreenOn = true
                    setShowSubtitleButton(true)
                    setShowNextButton(false)
                    setShowPreviousButton(false)
                    controllerShowTimeoutMs = 3_000
                    setControllerVisibilityListener(PlayerView.ControllerVisibilityListener { visibility -> controlsVisible = visibility == View.VISIBLE })
                    // So the remote's buttons reach the player straight away.
                    isFocusable = true
                    isFocusableInTouchMode = true
                    post { requestFocus() }
                }
            },
            update = { it.player = player },
            modifier = Modifier.fillMaxSize(),
        )
        if (controlsVisible || showSound) {
            Row(
                Modifier.fillMaxWidth().background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.7f), Color.Transparent)))
                    .padding(horizontal = 32.dp, vertical = 24.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f)) {
                    Text(item.displayTitle, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold, color = Color.White)
                    item.episodeTitle?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = Palette.muted) }
                }
                ActionButton("Sound", Icons.Default.GraphicEq, { showSound = !showSound }, primary = sound.isActive())
            }
        }
        if (showSound) {
            BackHandler { showSound = false }
            Column(
                Modifier.align(Alignment.TopEnd).padding(top = 88.dp, end = 24.dp).widthIn(max = 380.dp)
                    .background(Color(0xF0202024), MaterialTheme.shapes.large).padding(vertical = 12.dp),
            ) {
                Text("Sound", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = Color.White,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
                SoundControls()
            }
        }
        error?.let {
            Column(Modifier.align(Alignment.Center).widthIn(max = 520.dp).background(Color(0xE6202024), MaterialTheme.shapes.large).padding(24.dp)) {
                Text(it, color = Color.White)
                Button({ navigator.back() }, Modifier.padding(top = 16.dp)) { Text("Close") }
            }
        }
    }
}
