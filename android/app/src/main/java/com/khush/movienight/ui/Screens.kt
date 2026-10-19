package com.khush.movienight.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.outlined.CreateNewFolder
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilledTonalButton
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
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.khush.movienight.core.ContentKind
import com.khush.movienight.core.FilmShelves
import com.khush.movienight.core.HomeShelves
import com.khush.movienight.core.NaturalOrder
import com.khush.movienight.core.ShelfBuilder
import com.khush.movienight.core.TVLibrary
import com.khush.movienight.core.TVShowSummary
import com.khush.movienight.data.MediaItem

/** The library as a key → item map, plus a value snapshot for the shelf builders. */
private class Library(val items: List<MediaItem>) {
    val lookup = items.associateBy { it.key }
    val entries = items.map { it.browseEntry() }
    val homeVideos = items.filter { it.contentKind == ContentKind.HOME_VIDEO }
}

@Composable
private fun rememberLibrary(): Library? {
    val items by rememberApp().store.items.collectAsState()
    return remember(items) { items?.let(::Library) }
}

/** A scrolling page with an optional banner on top and rows below. */
@Composable
private fun ShelfPage(hero: (@Composable () -> Unit)?, title: String? = null, content: @Composable () -> Unit) {
    val metrics = LocalMetrics.current
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 48.dp)) {
        if (hero != null) item { hero() } else if (title != null) {
            item {
                Text(title, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold,
                    modifier = Modifier.pageTop().padding(horizontal = metrics.gutter, vertical = 16.dp))
            }
        }
        item { Spacer(Modifier.height(12.dp)) }
        item { content() }
    }
}

@Composable
fun HomeScreen(navigator: Navigator) {
    val library = rememberLibrary() ?: return
    val sources by rememberApp().store.sources.collectAsState()
    if (sources.isEmpty()) return EmptyLibrary(navigator)
    val shelves = remember(library) { HomeShelves.build(library.entries, library.homeVideos.map { it.shelfInput() }) }
    val hero = remember(library) { HomeShelves.heroKey(library.entries, library.homeVideos.map { it.shelfInput() })?.let(library.lookup::get) }
    ShelfPage(hero?.let { { Hero(it, navigator, takeFocus = true) } }, title = "Home") {
        Shelves(shelves, library.lookup, navigator::open)
    }
}

@Composable
fun FilmsScreen(navigator: Navigator) {
    val library = rememberLibrary() ?: return
    val films = remember(library) { library.entries.filter { it.kind == ContentKind.FILM } }
    val shelves = remember(library) { FilmShelves.build(library.entries) }
    val hero = remember(library) { HomeShelves.heroKey(films, emptyList())?.let(library.lookup::get) }
    val all = remember(library) { films.sortedWith(compareBy(NaturalOrder) { it.title }).mapNotNull { library.lookup[it.key] } }
    ShelfPage(hero?.let { { Hero(it, navigator, eyebrow = it.franchise, takeFocus = true) } }, title = "Films") {
        Column(verticalArrangement = Arrangement.spacedBy(LocalMetrics.current.rowSpacing)) {
            Shelves(shelves, library.lookup, navigator::open)
            ShelfRow("All Films", all, navigator::open)
        }
    }
}

@Composable
fun HomeVideosScreen(navigator: Navigator) {
    val library = rememberLibrary() ?: return
    val inputs = remember(library) { library.homeVideos.map { it.shelfInput() } }
    val shelves = remember(inputs) { ShelfBuilder.build(inputs) }
    val hero = remember(inputs) { HomeShelves.homeVideoHero(inputs)?.let(library.lookup::get) }
    ShelfPage(hero?.let { { Hero(it, navigator, takeFocus = true) } }, title = "Home Videos") {
        Shelves(shelves, library.lookup, navigator::open)
    }
}

@Composable
fun TvShowsScreen(navigator: Navigator) {
    val library = rememberLibrary() ?: return
    val shows = remember(library) { TVLibrary.shows(library.entries) }
    val metrics = LocalMetrics.current
    LazyVerticalGrid(
        GridCells.Adaptive(if (LocalFormFactor.current == FormFactor.PHONE) 150.dp else metrics.cardWidth + 20.dp),
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = metrics.gutter, end = metrics.gutter, bottom = 48.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        verticalArrangement = Arrangement.spacedBy(24.dp),
    ) {
        item(span = { androidx.compose.foundation.lazy.grid.GridItemSpan(maxLineSpan) }) {
            Text("TV Shows", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold,
                modifier = Modifier.pageTop().padding(vertical = 16.dp))
        }
        items(shows, key = { it.name }) { show -> ShowCard(show, library.lookup) { navigator.openShow(show.name) } }
    }
}

@Composable
private fun ShowCard(show: TVShowSummary, lookup: Map<String, MediaItem>, onOpen: () -> Unit) {
    val next = show.nextKey?.let(lookup::get)
    val cover = next ?: show.episodeKeys.firstOrNull()?.let(lookup::get)
    val seasons = if (show.seasons.size == 1) "1 season" else "${show.seasons.size} seasons"
    val episodes = if (show.episodeKeys.size == 1) "1 episode" else "${show.episodeKeys.size} episodes"
    val subtitle = listOfNotNull(seasons, episodes,
        if (show.lastPlayedAt != null && next != null) "Next: S${next.season ?: 1} E${next.episodeNumber}" else null).joinToString(" · ")
    val interaction = rememberCardInteraction()
    Column(Modifier.cardClick(interaction, onClick = onOpen)) {
        Artwork(cover, Modifier.fillMaxWidth().aspectRatio(16f / 9f).focusHighlight(interaction, RoundedCornerShape(12.dp)), cornerRadius = 12.dp)
        Spacer(Modifier.height(8.dp))
        Text(show.name, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(subtitle, style = MaterialTheme.typography.bodySmall, color = Palette.muted, maxLines = 1)
    }
}

/** One show: play what's next, pick a season, and its episodes in order with progress. */
@Composable
fun ShowScreen(name: String, navigator: Navigator) {
    val library = rememberLibrary() ?: return
    val app = rememberApp()
    val startFromBeginning by app.preferences.startFromBeginning.collectAsState()
    val show = remember(library) { TVLibrary.shows(library.entries).firstOrNull { it.name == name } } ?: return
    val episodes = show.episodeKeys.mapNotNull(library.lookup::get)
    val next = show.nextKey?.let(library.lookup::get)
    var season by rememberSaveable { mutableStateOf<Int?>(null) }
    val selected = season ?: next?.season ?: show.seasons.firstOrNull() ?: 1
    val metrics = LocalMetrics.current
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 48.dp)) {
        item {
            val banner = next ?: episodes.firstOrNull()
            Box(Modifier.fillMaxWidth().height(metrics.heroHeight * 0.85f)) {
                Artwork(banner, Modifier.fillMaxSize(), cornerRadius = 0.dp)
                Box(Modifier.fillMaxSize().background(androidx.compose.ui.graphics.Brush.verticalGradient(0.3f to Color.Transparent, 1f to Palette.ink)))
                Column(Modifier.align(Alignment.BottomStart).padding(horizontal = metrics.gutter, vertical = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(name, style = MaterialTheme.typography.displaySmall, fontWeight = FontWeight.Bold)
                    if (next != null) {
                        val number = "S${next.season ?: 1} E${next.episodeNumber ?: 1}"
                        val label = when {
                            next.resumePosition(startFromBeginning) != null -> "Resume $number"
                            show.lastPlayedAt == null -> "Play $number"
                            else -> "Next: $number"
                        }
                        val focus = remember { androidx.compose.ui.focus.FocusRequester() }
                        InitialFocus(focus, next.key)
                        ActionButton(label, Icons.Default.PlayArrow, { navigator.play(next) },
                            Modifier.focusRequester(focus), primary = true)
                    }
                }
            }
        }
        if (show.seasons.size > 1) {
            item {
                LazyRow(contentPadding = PaddingValues(horizontal = metrics.gutter, vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    items(show.seasons) { number ->
                        FilterChip(selected = number == selected, onClick = { season = number }, label = { Text("Season $number") })
                    }
                }
            }
        }
        items(episodes.filter { (it.season ?: 1) == selected }, key = { it.key }) { episode ->
            EpisodeRow(episode, isNext = episode.key == next?.key, onPlay = { navigator.play(episode) }, onDetails = { navigator.open(episode) })
        }
        val extras = show.extraKeys.mapNotNull(library.lookup::get)
        if (extras.isNotEmpty()) item { Spacer(Modifier.height(24.dp)); ShelfRow("Extras", extras, navigator::open) }
    }
}

@Composable
private fun EpisodeRow(item: MediaItem, isNext: Boolean, onPlay: () -> Unit, onDetails: () -> Unit) {
    val metrics = LocalMetrics.current
    var menu by remember { mutableStateOf(false) }
    Row(
        Modifier.fillMaxWidth().padding(horizontal = metrics.gutter, vertical = 8.dp)
            .focusCard(RoundedCornerShape(12.dp), onLongClick = { menu = true }, onClick = onPlay).padding(4.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Box(Modifier.width(if (LocalFormFactor.current == FormFactor.PHONE) 150.dp else 220.dp).aspectRatio(16f / 9f)) {
            Artwork(item, Modifier.fillMaxSize(), cornerRadius = 8.dp)
            if (item.progressFraction > 0.02 && !item.isFinished) ProgressBar(item.progressFraction, Modifier.align(Alignment.BottomCenter).padding(8.dp))
            if (item.isFinished) Chip("Watched", Modifier.align(Alignment.TopEnd).padding(6.dp))
            CardMenu(item, menu) { menu = false }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("${item.episodeNumber ?: 0}. ${item.episodeTitle ?: "Episode ${item.episodeNumber ?: 0}"}",
                    style = MaterialTheme.typography.titleMedium, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                if (isNext) Chip("UP NEXT")
            }
            Text(listOfNotNull(Formatters.duration(item.duration), Formatters.remaining(item.remainingSeconds)).joinToString(" · "),
                style = MaterialTheme.typography.bodySmall, color = Palette.muted)
            Text("Details", style = MaterialTheme.typography.labelMedium, color = Palette.muted,
                modifier = Modifier.focusCard(RoundedCornerShape(50), onClick = onDetails).padding(horizontal = 8.dp, vertical = 4.dp))
        }
    }
}

/** First run: what Movie Night does and where to start. */
@Composable
fun EmptyLibrary(navigator: Navigator) {
    Column(
        Modifier.fillMaxSize().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        androidx.compose.foundation.Image(
            androidx.compose.ui.res.painterResource(com.khush.movienight.R.drawable.logo_horizontal), "Movie Night",
            Modifier.height(56.dp),
        )
        Spacer(Modifier.height(24.dp))
        Text("Your films, shows and home videos, beautifully arranged.", style = MaterialTheme.typography.titleMedium,
            color = Palette.muted, modifier = Modifier.widthIn(max = 480.dp), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        Spacer(Modifier.height(28.dp))
        val focus = remember { androidx.compose.ui.focus.FocusRequester() }
        InitialFocus(focus, Unit)
        ActionButton("Add Videos", Icons.Outlined.CreateNewFolder, navigator::sources, Modifier.focusRequester(focus), primary = true)
    }
}
