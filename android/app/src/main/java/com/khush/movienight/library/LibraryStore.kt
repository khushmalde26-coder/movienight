package com.khush.movienight.library

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import com.khush.movienight.core.ClassifierInput
import com.khush.movienight.core.ContentClassifier
import com.khush.movienight.core.FolderContent
import com.khush.movienight.core.WatchHistory
import com.khush.movienight.data.LibraryDao
import com.khush.movienight.data.LibrarySource
import com.khush.movienight.data.MediaItem
import com.khush.movienight.data.SourceKind
import com.khush.movienight.data.WatchRecord
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID

/**
 * Owns folder access, scanning and enrichment. Screens read [items] and [sources]; this type does the writing.
 * A folder whose drive is unplugged keeps its videos (greyed out) until it's back, like the Apple app.
 */
class LibraryStore(private val context: Context, private val dao: LibraryDao) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val scanLock = Mutex()

    val sources: StateFlow<List<LibrarySource>> = dao.sources().stateIn(scope, SharingStarted.Eagerly, emptyList())
    val items: StateFlow<List<MediaItem>?> = dao.items().stateIn(scope, SharingStarted.Eagerly, null)

    private val _offline = MutableStateFlow<Set<String>>(emptySet())
    val offline: StateFlow<Set<String>> = _offline.asStateFlow()
    private val _scanning = MutableStateFlow<Set<String>>(emptySet())
    val scanning: StateFlow<Set<String>> = _scanning.asStateFlow()
    private val _lastError = MutableStateFlow<String?>(null)
    val lastError: StateFlow<String?> = _lastError.asStateFlow()

    // Sources

    fun addFolder(treeUri: Uri, content: FolderContent) = scope.launch {
        if (!keepAccess(treeUri)) return@launch
        val name = DocumentFile.fromTreeUri(context, treeUri)?.name ?: treeUri.lastPathSegment ?: "Folder"
        if (sources.value.any { it.uri == treeUri.toString() }) return@launch
        val source = LibrarySource(UUID.randomUUID().toString(), name, treeUri.toString(), SourceKind.FOLDER, content)
        dao.upsert(source)
        rescan(source)
    }

    /** Individual videos. Each becomes its own source with its own permission, so it behaves like a folder when its drive is away. */
    fun addFiles(uris: List<Uri>) = scope.launch {
        for (uri in uris) {
            if (sources.value.any { it.uri == uri.toString() } || !keepAccess(uri)) continue
            val name = DocumentFile.fromSingleUri(context, uri)?.name ?: "Video"
            val source = LibrarySource(UUID.randomUUID().toString(), name, uri.toString(), SourceKind.FILE)
            dao.upsert(source)
            rescan(source)
        }
    }

    /** Everything the system has indexed on this device and its USB drives. Needs the videos permission first. */
    fun addDeviceVideos(content: FolderContent) = scope.launch {
        if (sources.value.any { it.kind == SourceKind.DEVICE }) return@launch
        val source = LibrarySource(UUID.randomUUID().toString(), "This Device", "", SourceKind.DEVICE, content)
        dao.upsert(source)
        rescan(source)
    }

    private fun keepAccess(uri: Uri): Boolean = try {
        context.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        true
    } catch (e: SecurityException) {
        _lastError.value = "Movie Night couldn't keep access to that location."
        false
    }

    fun remove(source: LibrarySource) = scope.launch {
        val items = dao.items(source.id)
        archiveHistory(items)
        withContext(Dispatchers.IO) {
            val directory = MetadataReader.thumbnailDirectory(context)
            items.mapNotNull { it.thumbnailFile }.forEach { File(directory, it).delete() }
        }
        dao.delete(source)
        if (source.uri.isNotEmpty()) {
            runCatching { context.contentResolver.releasePersistableUriPermission(Uri.parse(source.uri), Intent.FLAG_GRANT_READ_URI_PERMISSION) }
        }
        _offline.update { it - source.id }
    }

    fun setContent(content: FolderContent, source: LibrarySource) = scope.launch {
        val updated = source.copy(content = content)
        dao.upsert(updated)
        dao.upsert(classify(updated, dao.items(source.id)))
    }

    // Scanning

    fun rescanAll() = scope.launch {
        for (source in dao.allSources()) rescan(source)
    }

    fun rescanSource(source: LibrarySource) = scope.launch { rescan(source) }

    /** Picks up drives that came back (and scans them) and marks ones that went away. Called when the app comes forward. */
    fun refreshAvailability() = rescanAll()

    suspend fun rescan(source: LibrarySource) {
        if (source.id in _scanning.value) return
        _scanning.update { it + source.id }
        try {
            scanLock.withLock { scan(source) }
        } finally {
            _scanning.update { it - source.id }
        }
    }

    private suspend fun scan(source: LibrarySource) {
        val resolver = context.contentResolver
        val files = try {
            withContext(Dispatchers.IO) {
                when (source.kind) {
                    SourceKind.FOLDER -> LibraryScanner.scanTree(resolver, Uri.parse(source.uri))
                    SourceKind.FILE -> listOf(LibraryScanner.scanFile(resolver, Uri.parse(source.uri)))
                    SourceKind.DEVICE -> LibraryScanner.scanDevice(resolver)
                }
            }
        } catch (e: Exception) {
            // Unplugged or permission gone: keep everything, grey it out.
            _offline.update { it + source.id }
            return
        }
        _offline.update { it - source.id }
        if (dao.source(source.id) == null) return   // removed while scanning

        val existing = dao.items(source.id).associateBy { it.key }.toMutableMap()
        val foundKeys = files.map { key(source, it.keyPath) }.toSet()
        // Keep the watch state of files that went away first, so a file that moved within this
        // folder gets it back below when it shows up at its new path.
        archiveHistory(existing.values.filter { it.key !in foundKeys })

        val thumbnails = MetadataReader.thumbnailDirectory(context)
        val scanned = files.map { file ->
            val key = key(source, file.keyPath)
            val found = existing.remove(key)
            if (found != null) {
                var item = found.copy(fileSize = file.size, collection = file.collection, relativePath = file.relativePath, uri = file.uri.toString(), modifiedAt = file.modifiedAt)
                // Caches can be cleared by the system; remake missing artwork.
                if (item.thumbnailFile != null && !File(thumbnails, item.thumbnailFile!!).exists()) item = item.copy(thumbnailFile = null, metadataVersion = 0)
                item
            } else {
                restoreHistory(MediaItem(
                    key = key, sourceId = source.id, relativePath = file.relativePath, collection = file.collection,
                    fileName = file.fileName, uri = file.uri.toString(), fileSize = file.size, modifiedAt = file.modifiedAt,
                ))
            }
        }
        // Whatever is left was deleted or moved on disk. Safe because we know the source is online.
        dao.replaceItems(classify(source, scanned), existing.keys.toList())
        dao.upsert(source.copy(lastScannedAt = System.currentTimeMillis()))

        enrich(source, scanned.filter { it.metadataVersion < MetadataReader.VERSION })
    }

    /** Reads length, date and artwork. Saves in batches so rows fill in progressively on a large first import. */
    private suspend fun enrich(source: LibrarySource, pending: List<MediaItem>) {
        if (pending.isEmpty()) return
        val batch = mutableListOf<MediaItem>()
        for (item in pending) {
            val metadata = withContext(Dispatchers.IO) {
                MetadataReader.read(context, Uri.parse(item.uri), item.key, makeThumbnail = item.thumbnailFile == null)
            }
            // The item may have changed (been played, removed) while reading; merge into the latest copy.
            val current = dao.item(item.key) ?: continue
            batch += current.copy(
                duration = metadata.duration, width = metadata.width, height = metadata.height, frameRate = metadata.frameRate,
                recordedAt = metadata.recordedAt, isPlayable = metadata.isPlayable,
                thumbnailFile = metadata.thumbnailFile ?: current.thumbnailFile, metadataVersion = MetadataReader.VERSION,
            )
            if (batch.size == 10) { dao.upsert(batch); batch.clear() }
        }
        dao.upsert(batch)
        // Lengths are known now, which settles short clips in folders left to guess.
        val latest = dao.source(source.id) ?: return
        if (latest.content == FolderContent.AUTO) dao.upsert(classify(latest, dao.items(source.id)))
    }

    private fun classify(source: LibrarySource, items: List<MediaItem>): List<MediaItem> {
        val results = ContentClassifier.classify(items.map { ClassifierInput(it.key, it.relativePath, it.fileName, it.duration) }, source.content)
        return items.map { item ->
            val result = results[item.key] ?: return@map item
            item.copy(
                kind = result.kind, cleanTitle = result.title, showName = result.show, season = result.season,
                episodeNumber = result.episode, episodeTitle = result.episodeTitle, releaseYear = result.year, franchise = result.franchise,
            )
        }
    }

    // Watch state

    fun saveProgress(key: String, seconds: Double, duration: Double?) = scope.launch {
        val item = dao.item(key) ?: return@launch
        val length = duration?.takeIf { it > 0 } ?: item.duration
        when {
            // Rewatching a finished video makes it in progress again, so it can resume.
            length != null && seconds / length > 0.95 -> dao.setWatchState(key, 0.0, System.currentTimeMillis(), true)
            seconds > 5 -> dao.setWatchState(key, seconds, System.currentTimeMillis(), false)
            else -> dao.setWatchState(key, seconds, System.currentTimeMillis(), item.isFinished)
        }
    }

    /** Played to the end. */
    fun finish(key: String) = scope.launch { dao.setWatchState(key, 0.0, System.currentTimeMillis(), true) }

    /** Takes a video off Continue Watching and forgets its place, so it next plays from the start. */
    fun removeFromContinueWatching(item: MediaItem) = scope.launch {
        dao.setWatchState(item.key, 0.0, null, item.isFinished)
    }

    fun setWatched(item: MediaItem, watched: Boolean) = scope.launch {
        dao.setWatchState(item.key, 0.0, if (watched) item.lastPlayedAt else null, watched)
    }

    fun clearError() { _lastError.value = null }

    // Watch history across moves

    private suspend fun archiveHistory(items: Collection<MediaItem>) {
        val records = items.filter { WatchHistory.hasHistory(it.progressSeconds, it.lastPlayedAt, it.isFinished) }.map {
            WatchRecord(nameKey = WatchHistory.nameKey(it.fileName), fileSize = it.fileSize, progressSeconds = it.progressSeconds,
                        lastPlayedAt = it.lastPlayedAt, isFinished = it.isFinished)
        }
        if (records.isNotEmpty()) dao.insert(records)
    }

    /** A new file whose name matches one that left the library takes over its watch state. */
    private suspend fun restoreHistory(item: MediaItem): MediaItem {
        val records = dao.records(WatchHistory.nameKey(item.fileName))
        val index = WatchHistory.bestMatch(item.fileSize, records.map { WatchHistory.Candidate(it.fileSize, it.savedAt) }) ?: return item
        val record = records[index]
        dao.deleteRecord(record.id)
        return item.copy(progressSeconds = record.progressSeconds, lastPlayedAt = record.lastPlayedAt, isFinished = record.isFinished)
    }

    companion object {
        fun key(source: LibrarySource, relativePath: String) = source.id + "/" + relativePath
    }
}
