package com.khush.movienight.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.khush.movienight.core.ContentKind

@Composable
fun DetailScreen(key: String, navigator: Navigator) {
    val app = rememberApp()
    val items by app.store.items.collectAsState()
    val sources by app.store.sources.collectAsState()
    val item = items?.firstOrNull { it.key == key } ?: return
    val metrics = LocalMetrics.current
    val related = items.orEmpty().filter { it.key != item.key && it.sourceId == item.sourceId && it.collection == item.collection && item.collection.isNotEmpty() }
        .sortedBy { it.displayTitle }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 48.dp)) {
        item { Hero(item, navigator, showsMoreInfo = false, onBack = { navigator.back() }, takeFocus = true) }
        item {
            Column(Modifier.padding(horizontal = metrics.gutter, vertical = 16.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    ActionButton(if (item.isFinished) "Mark as Unwatched" else "Mark as Watched", null, { app.store.setWatched(item, !item.isFinished) })
                    if (item.isInContinueWatching) {
                        ActionButton("Remove from Continue Watching", null, { app.store.removeFromContinueWatching(item) })
                    }
                }
                Text("Details", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    InfoRow("Length", Formatters.duration(item.duration))
                    if (item.contentKind == ContentKind.HOME_VIDEO) InfoRow("Recorded", Formatters.date(item.bestDate))
                    InfoRow("Resolution", Formatters.resolution(item.width, item.height))
                    InfoRow("Sound", item.spatial?.spoken)
                    InfoRow("Frame rate", item.frameRate?.let { "%.0f fps".format(it) })
                    InfoRow("Folder", item.collection.ifEmpty { null })
                    InfoRow("Library", sources.firstOrNull { it.id == item.sourceId }?.name)
                    InfoRow("File", item.fileName)
                    InfoRow("Size", Formatters.size(item.fileSize))
                }
            }
        }
        if (related.isNotEmpty()) item { ShelfRow("More from ${item.collection}", related, navigator::open) }
    }
}

@Composable
private fun InfoRow(label: String, value: String?) {
    if (value == null) return
    Row {
        Text(label, Modifier.width(120.dp), color = Palette.muted, style = MaterialTheme.typography.bodyMedium)
        Text(value, style = MaterialTheme.typography.bodyMedium)
    }
}
