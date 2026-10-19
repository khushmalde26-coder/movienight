package com.khush.movienight.ui

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.CreateNewFolder
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.FolderOff
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.PhoneAndroid
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.VideoFile
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.documentfile.provider.DocumentFile
import com.khush.movienight.core.FolderContent
import com.khush.movienight.data.LibrarySource
import com.khush.movienight.data.SourceKind

@Composable
private fun PageTitle(title: String, onBack: (() -> Unit)? = null) {
    Row(Modifier.pageTop().padding(horizontal = 8.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        if (onBack != null && LocalFormFactor.current != FormFactor.TV) IconButton(onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") }
        else Spacer(Modifier.width(LocalMetrics.current.gutter - 8.dp))
        Text(title, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun SectionHeader(text: String) {
    Text(text, style = MaterialTheme.typography.titleSmall, color = Palette.muted, fontWeight = FontWeight.SemiBold,
        modifier = Modifier.padding(start = LocalMetrics.current.gutter, top = 24.dp, bottom = 4.dp))
}

private val listColors @Composable get() = ListItemDefaults.colors(containerColor = Color.Transparent)

@Composable
fun SettingsScreen(navigator: Navigator) {
    val app = rememberApp()
    val startFromBeginning by app.preferences.startFromBeginning.collectAsState()
    val playIntro by app.preferences.playIntro.collectAsState()
    val scanning by app.store.scanning.collectAsState()
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 48.dp)) {
        item { PageTitle("Settings") }
        item { SectionHeader("Library") }
        item {
            ListItem(
                headlineContent = { Text("Folders and Videos") }, leadingContent = { Icon(Icons.Outlined.Folder, null) },
                colors = listColors, modifier = Modifier.focusCard(RoundedCornerShape(12.dp)) { navigator.sources() },
            )
        }
        item {
            ListItem(
                headlineContent = { Text("Rescan Library") }, leadingContent = { Icon(Icons.Outlined.Refresh, null) },
                trailingContent = { if (scanning.isNotEmpty()) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp) },
                colors = listColors, modifier = Modifier.focusCard(RoundedCornerShape(12.dp)) { app.store.rescanAll() },
            )
        }
        item { SectionHeader("Playback") }
        item {
            ListItem(
                headlineContent = { Text("Always Watch from Beginning") },
                supportingContent = { Text("Ignore where you stopped and start every video at the beginning.") },
                trailingContent = { Switch(startFromBeginning, null) }, colors = listColors,
                modifier = Modifier.focusCard(RoundedCornerShape(12.dp)) { app.preferences.setStartFromBeginning(!startFromBeginning) },
            )
        }
        item {
            ListItem(
                headlineContent = { Text("Play Intro at Launch") }, trailingContent = { Switch(playIntro, null) }, colors = listColors,
                modifier = Modifier.focusCard(RoundedCornerShape(12.dp)) { app.preferences.setPlayIntro(!playIntro) },
            )
        }
        item { SectionHeader("About") }
        item {
            val context = LocalContext.current
            val version = remember { context.packageManager.getPackageInfo(context.packageName, 0).versionName }
            ListItem(headlineContent = { Text("Movie Night for Android") }, supportingContent = { Text("Version $version") }, colors = listColors)
        }
    }
}

/** Folders, single videos and this device's videos, with what each holds and whether it's connected. */
@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
fun SourcesScreen(navigator: Navigator) {
    val app = rememberApp()
    val context = LocalContext.current
    val sources by app.store.sources.collectAsState()
    val items by app.store.items.collectAsState()
    val offline by app.store.offline.collectAsState()
    val scanning by app.store.scanning.collectAsState()
    val error by app.store.lastError.collectAsState()
    var pendingFolder by remember { mutableStateOf<Uri?>(null) }
    var pendingDevice by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    val counts = remember(items) { items.orEmpty().groupingBy { it.sourceId }.eachCount() }

    val folderPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri -> if (uri != null) pendingFolder = uri }
    val filePicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris -> if (uris.isNotEmpty()) app.store.addFiles(uris) }
    val videoPermission = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_VIDEO else Manifest.permission.READ_EXTERNAL_STORAGE
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) pendingDevice = true else message = "Movie Night needs access to videos to show the ones on this device."
    }

    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 48.dp)) {
        item { PageTitle("Folders and Videos") { navigator.back() } }
        item {
            androidx.compose.foundation.layout.FlowRow(Modifier.padding(horizontal = LocalMetrics.current.gutter, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                FilledTonalButton({
                    try { folderPicker.launch(null) } catch (_: ActivityNotFoundException) {
                        message = "This device has no folder picker. Use \"This Device's Videos\" to add videos on it and its USB drives."
                    }
                }) { Icon(Icons.Outlined.CreateNewFolder, null); Text("Add Folder", Modifier.padding(start = 8.dp)) }
                FilledTonalButton({
                    try { filePicker.launch(arrayOf("video/*")) } catch (_: ActivityNotFoundException) {
                        message = "This device has no file picker. Use \"This Device's Videos\" instead."
                    }
                }) { Icon(Icons.Outlined.VideoFile, null); Text("Add Videos", Modifier.padding(start = 8.dp)) }
                if (sources.none { it.kind == SourceKind.DEVICE }) {
                    FilledTonalButton({
                        if (ContextCompat.checkSelfPermission(context, videoPermission) == PackageManager.PERMISSION_GRANTED) pendingDevice = true
                        else permission.launch(videoPermission)
                    }) { Icon(Icons.Outlined.PhoneAndroid, null); Text("This Device's Videos", Modifier.padding(start = 8.dp)) }
                }
            }
        }
        (message ?: error)?.let { text ->
            item { Text(text, color = Color(0xFFFF8A80), modifier = Modifier.padding(horizontal = LocalMetrics.current.gutter, vertical = 8.dp)) }
        }
        if (sources.isEmpty()) {
            item {
                Text("Add a folder of films, TV shows or home videos. Movie Night keeps access to it, so it's still here next time, even after the drive has been unplugged.",
                    color = Palette.muted, modifier = Modifier.padding(LocalMetrics.current.gutter))
            }
        }
        items(sources, key = { it.id }) { source ->
            SourceRow(source, counts[source.id] ?: 0, source.id in offline, source.id in scanning)
            HorizontalDivider(Modifier.padding(horizontal = LocalMetrics.current.gutter), color = Color.White.copy(alpha = 0.08f))
        }
    }

    pendingFolder?.let { uri ->
        val name = remember(uri) { DocumentFile.fromTreeUri(context, uri)?.name ?: "this folder" }
        FolderSetupDialog("What's in \"$name\"?", onDismiss = { pendingFolder = null }) { content ->
            app.store.addFolder(uri, content)
            pendingFolder = null
        }
    }
    if (pendingDevice) {
        FolderSetupDialog("What are the videos on this device?", onDismiss = { pendingDevice = false }) { content ->
            app.store.addDeviceVideos(content)
            pendingDevice = false
        }
    }
}

@Composable
private fun SourceRow(source: LibrarySource, count: Int, offline: Boolean, scanning: Boolean) {
    val store = rememberApp().store
    var menu by remember { mutableStateOf(false) }
    val detail = when {
        offline && source.kind == SourceKind.FILE -> "Not connected. It stays in the library until it's back."
        offline -> "Not connected. Videos stay in the library until it's back."
        source.kind == SourceKind.FILE -> "Video"
        else -> "$count videos · ${source.content.title}"
    }
    ListItem(
        headlineContent = { Text(source.name) },
        supportingContent = { Text(detail) },
        leadingContent = {
            Icon(when { offline -> Icons.Outlined.FolderOff; source.kind == SourceKind.FILE -> Icons.Outlined.VideoFile
                        source.kind == SourceKind.DEVICE -> Icons.Outlined.PhoneAndroid; else -> Icons.Outlined.Folder }, null,
                tint = if (offline) Palette.muted else Palette.accent)
        },
        trailingContent = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (scanning) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                IconButton({ menu = true }) { Icon(Icons.Outlined.MoreVert, "Options for ${source.name}") }
                DropdownMenu(menu, { menu = false }) {
                    if (source.kind != SourceKind.FILE) {
                        FolderContent.entries.forEach { option ->
                            DropdownMenuItem(
                                text = { Text(option.title) },
                                leadingIcon = { RadioButton(source.content == option, null) },
                                onClick = { store.setContent(option, source); menu = false },
                            )
                        }
                        HorizontalDivider()
                    }
                    DropdownMenuItem(text = { Text("Rescan") }, onClick = { store.rescanSource(source); menu = false })
                    DropdownMenuItem(text = { Text("Remove from Library", color = Color(0xFFFF6961)) }, onClick = { store.remove(source); menu = false })
                }
            }
        },
        colors = listColors,
        modifier = Modifier.padding(horizontal = LocalMetrics.current.gutter - 16.dp),
    )
}

/** "What's in this folder?", asked when a folder is added, so films, TV and home videos each go to the right place. */
@Composable
fun FolderSetupDialog(title: String, onDismiss: () -> Unit, onAdd: (FolderContent) -> Unit) {
    var content by remember { mutableStateOf(FolderContent.FILMS_AND_TV) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                FolderContent.entries.forEach { option ->
                    Row(
                        Modifier.fillMaxWidth().selectable(content == option, onClick = { content = option }).padding(vertical = 8.dp),
                        verticalAlignment = Alignment.Top,
                    ) {
                        RadioButton(content == option, null)
                        Column(Modifier.padding(start = 12.dp)) {
                            Text(option.title, style = MaterialTheme.typography.titleSmall)
                            Text(option.summary, style = MaterialTheme.typography.bodySmall, color = Palette.muted)
                        }
                    }
                }
                Text("You can change this later in Folders and Videos.", style = MaterialTheme.typography.bodySmall, color = Palette.muted)
            }
        },
        confirmButton = { TextButton({ onAdd(content) }) { Text("Add") } },
        dismissButton = { TextButton(onDismiss) { Text("Cancel") } },
    )
}
