package app.movienight.core

import java.time.Instant

/**
 * Watch state is restored for a file that reappears with the same name (moved, or its folder
 * re-added). A renamed file starts fresh. Same rules as the Apple app.
 */
object WatchHistory {
    /** Below this a size is a cloud placeholder or otherwise not the real file size. */
    const val RELIABLE_SIZE: Long = 1_000_000

    data class Candidate(val fileSize: Long, val savedAt: Instant)

    fun nameKey(fileName: String): String = fileName.lowercase()

    fun hasHistory(progressSeconds: Double, lastPlayedAt: Instant?, isFinished: Boolean): Boolean =
        isFinished || progressSeconds > 0 || lastPlayedAt != null

    /**
     * Index of the record to restore for a file with this name, or null.
     * Camera names repeat (every phone has an IMG_0001.MOV), so when both sizes are real they must
     * match; moving a file never changes its size. The same size wins over a size we can't trust.
     */
    fun bestMatch(fileSize: Long, candidates: List<Candidate>): Int? {
        val sizeKnown = fileSize >= RELIABLE_SIZE
        return candidates.indices
            .filter { index ->
                val other = candidates[index].fileSize
                !(sizeKnown && other >= RELIABLE_SIZE && other != fileSize)
            }
            .maxWithOrNull(compareBy<Int>({ candidates[it].fileSize == fileSize }, { candidates[it].savedAt }))
    }
}

/** Every container the Apple app accepts. Playback support on Android depends on the codecs inside. */
object VideoFormats {
    val extensions: Set<String> = setOf(
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

    fun isVideo(fileName: String): Boolean = fileName.substringAfterLast('.', "").lowercase() in extensions
}
