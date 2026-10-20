package com.khush.movienight.ui

import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.outlined.Movie
import androidx.compose.material.icons.outlined.SurroundSound
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.khush.movienight.core.ContentKind
import com.khush.movienight.core.DisplayTitle
import com.khush.movienight.core.Shelf
import com.khush.movienight.data.MediaItem
import com.khush.movienight.library.MetadataReader
import java.io.File

/**
 * Clickable that also shows focus, for TV remotes and keyboards: a gentle lift and a white outline,
 * like the Apple TV app. Long press (or a long press of the remote's centre button) opens [onLongClick].
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun Modifier.focusCard(shape: RoundedCornerShape = RoundedCornerShape(10.dp), onLongClick: (() -> Unit)? = null, onClick: () -> Unit): Modifier {
    var focused by remember { mutableStateOf(false) }
    val scale by animateFloatAsState(if (focused) 1.06f else 1f, label = "focus")
    return this
        .graphicsLayer { scaleX = scale; scaleY = scale }
        .onFocusChanged { focused = it.isFocused }
        .then(if (focused) Modifier.border(3.dp, Palette.focus, shape) else Modifier)
        .clip(shape)
        .combinedClickable(onLongClick = onLongClick, onClick = onClick)
}

/**
 * A whole card (artwork and titles) as one button, with the focus highlight on its artwork only,
 * as on the Apple TV app. Put [cardClick] on the card and [focusHighlight] on the artwork.
 */
class CardInteraction(val source: MutableInteractionSource)

@Composable
fun rememberCardInteraction() = remember { CardInteraction(MutableInteractionSource()) }

@OptIn(ExperimentalFoundationApi::class)
fun Modifier.cardClick(interaction: CardInteraction, onLongClick: (() -> Unit)? = null, onClick: () -> Unit): Modifier =
    combinedClickable(interactionSource = interaction.source, indication = null, onLongClick = onLongClick, onClick = onClick)

@Composable
fun Modifier.focusHighlight(interaction: CardInteraction, shape: RoundedCornerShape = RoundedCornerShape(10.dp)): Modifier {
    val focused by interaction.source.collectIsFocusedAsState()
    val pressed by interaction.source.collectIsPressedAsState()
    val scale by animateFloatAsState(if (focused) 1.06f else if (pressed) 0.97f else 1f, label = "focus")
    return graphicsLayer { scaleX = scale; scaleY = scale }
        .then(if (focused) Modifier.border(3.dp, Palette.focus, shape) else Modifier)
        .clip(shape)
}

/** A frame from the video, or a tinted placeholder until there is one. */
@Composable
fun Artwork(item: MediaItem?, modifier: Modifier = Modifier, cornerRadius: Dp = 10.dp) {
    val context = LocalContext.current
    val file = item?.thumbnailFile?.let { File(MetadataReader.thumbnailDirectory(context), it) }
    // Stable per-item colour so placeholders don't all look identical.
    val hue = ((item?.key ?: "").sumOf { it.code } % 360).toFloat()
    Box(
        modifier
            .clip(RoundedCornerShape(cornerRadius))
            .background(Brush.linearGradient(listOf(Color.hsv(hue, 0.5f, 0.35f), Color.hsv(hue, 0.6f, 0.15f)))),
        contentAlignment = Alignment.Center,
    ) {
        if (file != null) {
            AsyncImage(model = file, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        } else {
            Icon(Icons.Outlined.Movie, null, tint = Color.White.copy(alpha = 0.35f), modifier = Modifier.size(40.dp))
        }
    }
}

@Composable
fun ProgressBar(fraction: Double, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxWidth().height(4.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.3f))) {
        Box(Modifier.fillMaxWidth(fraction.toFloat()).height(4.dp).clip(CircleShape).background(Palette.accent))
    }
}

@Composable
fun Chip(text: String, modifier: Modifier = Modifier) {
    Text(
        text, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold, color = Color.White,
        modifier = modifier.background(Color.Black.copy(alpha = 0.6f), RoundedCornerShape(6.dp)).padding(horizontal = 6.dp, vertical = 2.dp),
    )
}

/** Outlined label beside a title, like "4K" or the Atmos chip with its little surround symbol. */
@Composable
fun QualityChip(text: String, icon: androidx.compose.ui.graphics.vector.ImageVector? = null) {
    Row(
        Modifier.border(1.dp, Palette.muted.copy(alpha = 0.6f), RoundedCornerShape(3.dp)).padding(horizontal = 4.dp, vertical = 1.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) {
            Icon(icon, null, tint = Palette.muted, modifier = Modifier.size(11.dp))
            Spacer(Modifier.width(2.dp))
        }
        Text(text, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold, color = Palette.muted)
    }
}

/** The chip for Dolby Atmos or DTS:X, when the video has it. */
@Composable
fun SpatialAudioChip(item: MediaItem) {
    item.spatial?.let { QualityChip(it.badge, Icons.Outlined.SurroundSound) }
}

/** The line under a card's title: when or where, since the length is stamped on the artwork. */
fun subtitle(item: MediaItem): String? = when (item.contentKind) {
    ContentKind.EPISODE -> item.episodeLabel
    ContentKind.FILM -> item.year?.toString() ?: item.franchise
    ContentKind.EXTRA -> item.showName
    ContentKind.HOME_VIDEO ->
        // Camera-named clips are already titled by date, so they show their folder instead.
        if (DisplayTitle.isCameraName(DisplayTitle.stem(item.fileName)) && item.bestDate != null) item.collection.ifEmpty { null }
        else Formatters.date(item.bestDate)
}

@Composable
fun PosterCard(item: MediaItem, onOpen: (MediaItem) -> Unit, modifier: Modifier = Modifier, width: Dp = LocalMetrics.current.cardWidth) {
    val app = rememberApp()
    val offline by app.store.offline.collectAsState()
    var menu by remember { mutableStateOf(false) }
    val available = item.sourceId !in offline
    val label = listOfNotNull(item.displayTitle, subtitle(item), Formatters.duration(item.duration), item.spatial?.spoken,
        if (item.isFinished) "watched" else null, if (!available) "offline" else null).joinToString(", ")
    val interaction = rememberCardInteraction()
    Column(modifier.width(width).cardClick(interaction, onLongClick = { menu = true }) { onOpen(item) }
        .semantics(mergeDescendants = true) { contentDescription = label }) {
        Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f).focusHighlight(interaction)) {
            Artwork(item, Modifier.fillMaxSize().graphicsLayer { alpha = if (available) 1f else 0.4f })
            if (item.progressFraction > 0.02 && !item.isFinished) {
                ProgressBar(item.progressFraction, Modifier.align(Alignment.BottomCenter).padding(10.dp))
            } else {
                Formatters.clock(item.duration)?.let { Chip(it, Modifier.align(Alignment.BottomEnd).padding(8.dp)) }
            }
            if (item.isFinished) {
                Icon(Icons.Default.Check, "Watched", tint = Color.White,
                    modifier = Modifier.align(Alignment.TopEnd).padding(8.dp).size(22.dp).background(Color.Black.copy(alpha = 0.6f), CircleShape).padding(3.dp))
            }
            CardMenu(item, menu) { menu = false }
        }
        Spacer(Modifier.height(8.dp))
        Text(item.displayTitle, style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            subtitle(item)?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = Palette.muted, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false))
            }
            SpatialAudioChip(item)
        }
    }
}

/** Long-press actions on a card. */
@Composable
fun CardMenu(item: MediaItem, expanded: Boolean, onDismiss: () -> Unit) {
    val store = rememberApp().store
    DropdownMenu(expanded = expanded, onDismissRequest = onDismiss) {
        DropdownMenuItem(text = { Text(if (item.isFinished) "Mark as Unwatched" else "Mark as Watched") }, onClick = {
            store.setWatched(item, !item.isFinished); onDismiss()
        })
        if (item.isInContinueWatching) {
            DropdownMenuItem(text = { Text("Remove from Continue Watching") }, onClick = { store.removeFromContinueWatching(item); onDismiss() })
        }
    }
}

/**
 * A titled reel of cards. The count beside the title drops it down into a grid of everything
 * in the row (and folds it back), which is easier with hundreds of videos.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ShelfRow(title: String, items: List<MediaItem>, onOpen: (MediaItem) -> Unit, modifier: Modifier = Modifier) {
    if (items.isEmpty()) return
    val metrics = LocalMetrics.current
    var expanded by rememberSaveable(title) { mutableStateOf(false) }
    val isTv = LocalFormFactor.current == FormFactor.TV
    Column(modifier.fillMaxWidth().animateContentSize()) {
        Row(Modifier.padding(horizontal = metrics.gutter), verticalAlignment = Alignment.CenterVertically) {
            Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
            if (items.size > 1) {
                Spacer(Modifier.width(10.dp))
                val expandLabel = if (expanded) "Show $title as a row" else "Show all ${items.size} in $title as a grid"
                Row(
                    // Rows scroll with the remote, so on TV the grid toggle stays out of the way of focus.
                    Modifier.focusProperties { canFocus = !isTv }
                        .focusCard(RoundedCornerShape(50)) { expanded = !expanded }
                        .background(Color.White.copy(alpha = 0.1f), RoundedCornerShape(50))
                        .padding(horizontal = 10.dp, vertical = 4.dp)
                        .semantics { contentDescription = expandLabel },
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("${items.size}", style = MaterialTheme.typography.labelLarge, color = Palette.muted)
                    Icon(Icons.Default.KeyboardArrowDown, null, tint = Palette.muted, modifier = Modifier.size(18.dp).rotate(if (expanded) 180f else 0f))
                }
            }
        }
        Spacer(Modifier.height(10.dp))
        if (expanded) {
            FlowRow(
                Modifier.padding(horizontal = metrics.gutter),
                horizontalArrangement = Arrangement.spacedBy(16.dp),
                verticalArrangement = Arrangement.spacedBy(20.dp),
            ) { items.forEach { PosterCard(it, onOpen) } }
        } else {
            LazyRow(
                contentPadding = PaddingValues(horizontal = metrics.gutter, vertical = 6.dp),
                horizontalArrangement = Arrangement.spacedBy(16.dp),
            ) { items(items, key = { it.key }) { PosterCard(it, onOpen) } }
        }
    }
}

/** Rows from the shelf builders, resolved to the library's items. */
@Composable
fun Shelves(shelves: List<Shelf>, lookup: Map<String, MediaItem>, onOpen: (MediaItem) -> Unit) {
    val metrics = LocalMetrics.current
    Column(verticalArrangement = Arrangement.spacedBy(metrics.rowSpacing)) {
        for (shelf in shelves) {
            ShelfRow(shelf.title, shelf.itemKeys.mapNotNull { lookup[it] }, onOpen)
        }
    }
}

/**
 * A pill button that's clear from across the room: solid white with black text when focused (or when
 * [primary]), frosted otherwise, like the Apple TV app's buttons. Works the same with touch.
 */
@Composable
fun ActionButton(
    text: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    primary: Boolean = false,
    enabled: Boolean = true,
) {
    val interaction = rememberCardInteraction()
    val focused by interaction.source.collectIsFocusedAsState()
    val pressed by interaction.source.collectIsPressedAsState()
    val solid = primary || focused
    val scale by animateFloatAsState(if (focused) 1.08f else if (pressed) 0.96f else 1f, label = "button")
    Row(
        modifier
            .graphicsLayer { scaleX = scale; scaleY = scale; alpha = if (enabled) 1f else 0.4f }
            .clip(RoundedCornerShape(50))
            .background(if (solid) Color.White else Color.White.copy(alpha = 0.16f))
            .then(if (focused && primary) Modifier.border(3.dp, Palette.muted, RoundedCornerShape(50)) else Modifier)
            .combinedClickable(interactionSource = interaction.source, indication = null, enabled = enabled, onClick = onClick)
            .padding(horizontal = 20.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val color = if (solid) Color.Black else Color.White
        if (icon != null) {
            Icon(icon, null, tint = color, modifier = Modifier.size(20.dp))
            Spacer(Modifier.width(8.dp))
        }
        Text(text, color = color, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold)
    }
}

/** Gives [requester] focus once it's on screen (TV only), so OK on the remote does the obvious thing. */
@Composable
fun InitialFocus(requester: androidx.compose.ui.focus.FocusRequester, key: Any?) {
    if (LocalFormFactor.current != FormFactor.TV) return
    androidx.compose.runtime.LaunchedEffect(key) {
        repeat(10) {
            kotlinx.coroutines.delay(100)
            if (runCatching { requester.requestFocus() }.isSuccess) return@LaunchedEffect
        }
    }
}

/** Top of a page without a banner: below the status bar, and below the floating tab bar on TV. */
@Composable
fun Modifier.pageTop(): Modifier =
    statusBarsPadding().padding(top = if (LocalFormFactor.current == FormFactor.TV) 64.dp else 0.dp)
