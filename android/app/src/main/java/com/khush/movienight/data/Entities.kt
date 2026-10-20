package com.khush.movienight.data

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import com.khush.movienight.core.BrowseEntry
import com.khush.movienight.core.ContentKind
import com.khush.movienight.core.DisplayTitle
import com.khush.movienight.core.FolderContent
import com.khush.movienight.core.ShelfInput
import com.khush.movienight.core.SpatialAudio
import com.khush.movienight.core.yearInstant
import java.time.Instant

/** Where a source's videos come from. */
enum class SourceKind {
    /** A folder or drive picked with the system picker; access survives restarts. */
    FOLDER,
    /** One video picked on its own. */
    FILE,
    /** Every video the system knows about on this device and its USB drives (for TVs without a folder picker). */
    DEVICE,
}

@Entity(tableName = "sources")
data class LibrarySource(
    @PrimaryKey val id: String,
    val name: String,
    /** Tree URI for a folder, document URI for a file, empty for device videos. */
    val uri: String,
    val kind: SourceKind,
    val content: FolderContent = FolderContent.AUTO,
    val titleChek: Boolean = false,
    val addedAt: Long = System.currentTimeMillis(),
    val lastScannedAt: Long? = null,
)

/** One video file inside a source. Paths are kept relative to the source, so a drive that comes back still matches. */
@Entity(
    tableName = "items",
    indices = [Index("sourceId")],
    foreignKeys = [ForeignKey(entity = LibrarySource::class, parentColumns = ["id"], childColumns = ["sourceId"], onDelete = ForeignKey.CASCADE)],
)
data class MediaItem(
    /** "<source id>/<relative path>", stable across rescans. */
    @PrimaryKey val key: String,
    val sourceId: String,
    val relativePath: String,
    /** Top-level folder inside the source, used for collection rows. Empty for files at the root. */
    val collection: String,
    val fileName: String,
    /** content:// URI the players open. */
    val uri: String,
    val fileSize: Long,
    val modifiedAt: Long?,
    val addedAt: Long = System.currentTimeMillis(),

    // Filled in by MetadataReader.
    val recordedAt: Long? = null,
    val duration: Double? = null,
    /** null until checked or when the system reader couldn't say; false means it has no video track. */
    val isPlayable: Boolean? = null,
    val thumbnailFile: String? = null,
    val width: Int? = null,
    val height: Int? = null,
    val frameRate: Double? = null,
    /** SpatialAudio name read from the soundtrack; null for none or not yet read. */
    val spatialAudio: String? = null,
    /** MetadataReader.VERSION that last read this file; lower means re-read on next scan. */
    val metadataVersion: Int = 0,

    // Set by ContentClassifier on every scan, from names and folders.
    val kind: ContentKind? = null,
    val cleanTitle: String? = null,
    val showName: String? = null,
    val season: Int? = null,
    val episodeNumber: Int? = null,
    val episodeTitle: String? = null,
    val releaseYear: Int? = null,
    val franchise: String? = null,

    // Watch state.
    val progressSeconds: Double = 0.0,
    val lastPlayedAt: Long? = null,
    val isFinished: Boolean = false,
) {
    val contentKind: ContentKind
        get() = kind ?: if (DisplayTitle.isCameraName(DisplayTitle.stem(fileName))) ContentKind.HOME_VIDEO else ContentKind.FILM

    /** When a home video was shot. Films and episodes have none: their file dates are when they were copied. */
    val bestDate: Instant?
        get() = if (contentKind == ContentKind.HOME_VIDEO) (recordedAt ?: modifiedAt)?.let(Instant::ofEpochMilli) else null

    val year: Int? get() = releaseYear

    val sortDate: Instant?
        get() = if (contentKind == ContentKind.HOME_VIDEO) bestDate else year?.let(::yearInstant)

    val progressFraction: Double
        get() = duration?.takeIf { it > 0 }?.let { (progressSeconds / it).coerceIn(0.0, 1.0) } ?: 0.0

    val isInContinueWatching: Boolean get() = !isFinished && progressFraction > 0.02 && lastPlayedAt != null

    val remainingSeconds: Double?
        get() = duration?.takeIf { progressSeconds > 0 && !isFinished }?.let { (it - progressSeconds).coerceAtLeast(0.0) }

    val isVertical: Boolean get() = width != null && height != null && height > width

    /** Dolby Atmos or DTS:X, from the soundtrack or, failing that, the file name. */
    val spatial: SpatialAudio?
        get() = spatialAudio?.let { name -> SpatialAudio.entries.firstOrNull { it.name == name } } ?: SpatialAudio.fromFileName(fileName)

    val isUHD: Boolean get() = (width ?: 0) >= 3200 || (height ?: 0) >= 2000

    /** "S4 E9" or "S4 E9 · The Wedding". */
    val episodeLabel: String?
        get() {
            if (contentKind != ContentKind.EPISODE || episodeNumber == null) return null
            val number = "S${season ?: 1} E$episodeNumber"
            return episodeTitle?.let { "$number · $it" } ?: number
        }

    val displayTitle: String
        get() = when (contentKind) {
            ContentKind.HOME_VIDEO -> DisplayTitle.make(fileName, bestDate)
            ContentKind.EPISODE -> listOfNotNull(showName, episodeNumber?.let { "S${season ?: 1} E$it" }).joinToString(" ")
            ContentKind.FILM, ContentKind.EXTRA -> cleanTitle ?: DisplayTitle.clean(DisplayTitle.stem(fileName))
        }

    /** Where playback starts: the saved position, or null to start from the beginning. */
    fun resumePosition(startFromBeginning: Boolean): Double? =
        if (startFromBeginning || isFinished || progressSeconds <= 5) null else progressSeconds

    fun browseEntry(): BrowseEntry = BrowseEntry(
        key = key, title = displayTitle, collection = collection, date = sortDate, addedAt = Instant.ofEpochMilli(addedAt),
        duration = duration, progressFraction = progressFraction, isFinished = isFinished, kind = contentKind, show = showName,
        season = season, episode = episodeNumber, franchise = franchise, isUHD = isUHD,
        lastPlayedAt = lastPlayedAt?.let(Instant::ofEpochMilli), year = year,
    )

    fun shelfInput(): ShelfInput = ShelfInput(
        key = key, collection = collection, date = bestDate, addedAt = Instant.ofEpochMilli(addedAt),
        progressFraction = progressFraction, duration = duration, isVertical = isVertical,
        lastPlayedAt = lastPlayedAt?.let(Instant::ofEpochMilli), isFinished = isFinished,
    )
}

/** Watch state of a file that left the library, kept so it comes back if the file reappears elsewhere. */
@Entity(tableName = "watch_records", indices = [Index("nameKey")])
data class WatchRecord(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val nameKey: String,
    val fileSize: Long,
    val progressSeconds: Double,
    val lastPlayedAt: Long?,
    val isFinished: Boolean,
    val savedAt: Long = System.currentTimeMillis(),
)
