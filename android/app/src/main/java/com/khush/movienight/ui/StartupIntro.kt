package com.khush.movienight.ui

import androidx.annotation.OptIn
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.RawResourceDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import com.khush.movienight.R
import kotlinx.coroutines.delay

/** The opening logo animation, the same one as on iPhone, iPad and Mac. A tap or any key skips it. */
@OptIn(UnstableApi::class)
@Composable
fun StartupIntro(onFinished: () -> Unit) {
    val context = LocalContext.current
    var leaving by remember { mutableStateOf(false) }
    val alpha by animateFloatAsState(if (leaving) 0f else 1f, tween(400), label = "intro", finishedListener = { if (leaving) onFinished() })
    val player = remember {
        ExoPlayer.Builder(context).build().apply {
            setMediaItem(MediaItem.fromUri(RawResourceDataSource.buildRawResourceUri(R.raw.startup)))
            volume = 0f
            prepare()
            playWhenReady = true
        }
    }
    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) { if (state == Player.STATE_ENDED) leaving = true }
            // The animation is 1440p60 HEVC, as on the Apple devices. Devices that can't decode it skip it.
            override fun onTracksChanged(tracks: androidx.media3.common.Tracks) {
                if (!tracks.isEmpty && !tracks.isTypeSupported(androidx.media3.common.C.TRACK_TYPE_VIDEO)) leaving = true
            }
            override fun onPlayerError(error: androidx.media3.common.PlaybackException) { leaving = true }
        }
        player.addListener(listener)
        onDispose { player.removeListener(listener); player.release() }
    }
    // Never hold the app hostage if the video stalls.
    LaunchedEffect(Unit) { delay(7_000); leaving = true }
    val focus = remember { FocusRequester() }
    // On TV the intro takes the remote's keys so any button skips it; touch devices skip it with a tap.
    val isTv = LocalFormFactor.current == FormFactor.TV
    LaunchedEffect(Unit) { if (isTv) runCatching { focus.requestFocus() } }
    Box(
        Modifier.fillMaxSize().graphicsLayer { this.alpha = alpha }.background(Color.Black)
            .focusRequester(focus).focusable().onKeyEvent { leaving = true; true }
            .clickable(remember { MutableInteractionSource() }, indication = null) { leaving = true },
    ) {
        // The logo until the first frame, so a slow start never looks frozen.
        androidx.compose.foundation.Image(
            androidx.compose.ui.res.painterResource(R.drawable.logo_horizontal), null,
            Modifier.align(androidx.compose.ui.Alignment.Center).fillMaxWidth(0.4f),
        )
        AndroidView({
            PlayerView(it).apply {
                this.player = player
                useController = false
                resizeMode = AspectRatioFrameLayout.RESIZE_MODE_ZOOM
                setShutterBackgroundColor(android.graphics.Color.TRANSPARENT)
            }
        }, Modifier.fillMaxSize())
    }
}
