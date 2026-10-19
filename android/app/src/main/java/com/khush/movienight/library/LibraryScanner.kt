package com.khush.movienight.library

import android.content.ContentResolver
import android.content.ContentUris
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import com.khush.movienight.core.VideoFormats

data class ScannedFile(
    val relativePath: String,
    val fileName: String,
    val uri: Uri,
    val size: Long,
    val modifiedAt: Long?,
    /** What the item's key is built from; differs from [relativePath] only for this device's videos. */
    val keyPath: String = relativePath,
) {
    /** Top-level folder, used for collection rows. */
    val collection: String get() = relativePath.split('/').let { if (it.size > 1) it[0] else "" }
}

/** Lists the videos in a source. Reading a folder that has gone away throws, which marks it offline. */
object LibraryScanner {
    private val documentColumns = arrayOf(
        DocumentsContract.Document.COLUMN_DOCUMENT_ID,
        DocumentsContract.Document.COLUMN_DISPLAY_NAME,
        DocumentsContract.Document.COLUMN_MIME_TYPE,
        DocumentsContract.Document.COLUMN_SIZE,
        DocumentsContract.Document.COLUMN_LAST_MODIFIED,
    )

    /** Every video below a folder picked with the system picker. */
    fun scanTree(resolver: ContentResolver, treeUri: Uri): List<ScannedFile> {
        val files = mutableListOf<ScannedFile>()
        // Iterative, so a deep tree can't overflow the stack.
        val pending = ArrayDeque(listOf(DocumentsContract.getTreeDocumentId(treeUri) to ""))
        var first = true
        while (pending.isNotEmpty()) {
            val (documentId, prefix) = pending.removeFirst()
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, documentId)
            val cursor = resolver.query(children, documentColumns, null, null, null)
            if (cursor == null) {
                // The root must be readable; a subfolder that vanished mid-scan is just skipped.
                if (first) throw IllegalStateException("Folder isn't available") else continue
            }
            first = false
            cursor.use {
                while (it.moveToNext()) {
                    val id = it.getString(0) ?: continue
                    val name = it.getString(1) ?: continue
                    if (name.startsWith(".")) continue
                    val path = if (prefix.isEmpty()) name else "$prefix/$name"
                    if (it.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) {
                        pending += id to path
                    } else if (VideoFormats.isVideo(name)) {
                        files += ScannedFile(
                            relativePath = path, fileName = name, uri = DocumentsContract.buildDocumentUriUsingTree(treeUri, id),
                            size = if (it.isNull(3)) 0 else it.getLong(3), modifiedAt = if (it.isNull(4)) null else it.getLong(4),
                        )
                    }
                }
            }
        }
        return files
    }

    /** A single picked video. */
    fun scanFile(resolver: ContentResolver, uri: Uri): ScannedFile {
        val cursor = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)
            ?: throw IllegalStateException("Video isn't available")
        cursor.use {
            if (!it.moveToFirst()) throw IllegalStateException("Video isn't available")
            val name = it.getString(0) ?: uri.lastPathSegment ?: "Video"
            return ScannedFile(name, name, uri, if (it.isNull(1)) 0 else it.getLong(1), null)
        }
    }

    /** Videos the system has indexed on this device and its USB drives, arranged by their folders. */
    fun scanDevice(resolver: ContentResolver): List<ScannedFile> {
        val collection = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        val columns = arrayOf(
            MediaStore.Video.Media._ID, MediaStore.Video.Media.DISPLAY_NAME, MediaStore.Video.Media.SIZE,
            MediaStore.Video.Media.DATE_MODIFIED, MediaStore.Video.Media.DATA,
        )
        data class Row(val uri: Uri, val name: String, val size: Long, val modified: Long?, val path: String)
        val rows = mutableListOf<Row>()
        resolver.query(collection, columns, null, null, null)?.use {
            while (it.moveToNext()) {
                val name = it.getString(1) ?: continue
                // DATA is deprecated but still the one column with the folder on every Android version.
                @Suppress("DEPRECATION")
                val path = it.getString(4) ?: name
                rows += Row(ContentUris.withAppendedId(collection, it.getLong(0)), name, it.getLong(2),
                            it.getLong(3).takeIf { seconds -> seconds > 0 }?.times(1000), path)
            }
        }
        val arranged = DevicePaths.arrange(rows.map { it.path })
        return rows.mapIndexed { index, row ->
            ScannedFile(arranged[index].relative, row.name, row.uri, row.size, row.modified, keyPath = arranged[index].full)
        }
    }
}

/**
 * Turns absolute paths of videos on a device into library paths. Each top-level folder (Movies, DCIM,
 * Download, a USB drive's folders) is treated like a folder the user picked: the folders every video
 * in it shares are dropped, so Movies/Films/007/Skyfall.mp4 becomes 007/Skyfall.mp4 and the 007
 * franchise and TV show folders are found as they are in a picked folder.
 */
object DevicePaths {
    data class Arranged(val full: String, val relative: String)

    fun arrange(paths: List<String>): List<Arranged> {
        val volumeRelative = paths.map(::volumeRelative)
        val prefixes = volumeRelative.groupBy { it.first() }.mapValues { (_, group) -> commonFolders(group) }
        return volumeRelative.map { segments ->
            val drop = prefixes.getValue(segments.first())
            Arranged(segments.joinToString("/"), segments.drop(drop).joinToString("/"))
        }
    }

    /** "/storage/emulated/0/Movies/a.mp4" → [Movies, a.mp4]; "/storage/1A2B-3C4D/Films/a.mp4" → [1A2B-3C4D, Films, a.mp4]. */
    private fun volumeRelative(path: String): List<String> {
        val parts = path.split('/').filter { it.isNotEmpty() }
        val skip = when {
            parts.size > 3 && parts[0] == "storage" && parts[1] == "emulated" -> 3
            parts.size > 2 && parts[0] == "storage" -> 1        // keep the drive's name so drives don't mix
            parts.size > 3 && parts[0] == "mnt" -> 3
            else -> 0
        }
        return parts.drop(skip).ifEmpty { listOf(path) }
    }

    /** How many leading folders every path in the group shares (never the file name itself). */
    private fun commonFolders(group: List<List<String>>): Int {
        var count = 0
        val shortest = group.minOf { it.size } - 1
        while (count < shortest && group.all { it[count] == group[0][count] }) count++
        return count
    }
}
