package com.khush.movienight.core

/**
 * Watch state survives a file moving within the library: when a file leaves, its state is kept under
 * its name, and a new file with the same name takes it over. Renaming a file starts it fresh.
 */
object WatchHistory {
    /** Below this a size is a cloud placeholder or otherwise not the real file size. */
    const val RELIABLE_SIZE = 1_000_000L

    data class Candidate(val fileSize: Long, val savedAt: Long)

    fun nameKey(fileName: String): String = fileName.lowercase()

    fun hasHistory(progressSeconds: Double, lastPlayedAt: Long?, isFinished: Boolean): Boolean =
        isFinished || progressSeconds > 0 || lastPlayedAt != null

    /**
     * Index of the record to restore for a file with this name, or null.
     * Camera names repeat (every phone has an IMG_0001.MOV), so when both sizes are real they must
     * match; moving a file never changes its size. The same size wins over a size we can't trust.
     */
    fun bestMatch(fileSize: Long, candidates: List<Candidate>): Int? {
        val sizeKnown = fileSize >= RELIABLE_SIZE
        val usable = candidates.indices.filter { index ->
            val other = candidates[index].fileSize
            !(sizeKnown && other >= RELIABLE_SIZE && other != fileSize)
        }
        return usable.maxWithOrNull(compareBy<Int>({ candidates[it].fileSize == fileSize }, { candidates[it].savedAt }))
    }
}

/** Every extension either player might open, as on the Apple app. */
object VideoFormats {
    val extensions = setOf(
        // Apple / MPEG-4 family
        "mov", "qt", "mp4", "m4v", "3gp", "3g2",
        // Matroska / WebM / Ogg
        "mkv", "mk3d", "webm", "ogv", "ogg",
        // MPEG program and transport streams, DVD and camcorder
        "mpg", "mpeg", "mpe", "mpv", "mp2", "m2v", "vob", "ts", "mts", "m2ts",
        // Windows
        "avi", "divx", "xvid", "wmv", "asf",
        // Flash
        "flv", "f4v",
        // Professional and older formats
        "mxf", "rm", "rmvb", "viv", "nsv", "roq", "svi", "amv", "drc",
    )

    fun isVideo(fileName: String) = DisplayTitle.extension(fileName) in extensions
}
