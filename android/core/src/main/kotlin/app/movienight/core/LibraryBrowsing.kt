package app.movienight.core

import java.text.Normalizer
import java.time.Instant
import java.time.ZoneId
import java.time.format.TextStyle
import java.util.Locale

/** One video as the Library, Collections and section screens see it. A value, so the logic is pure and tested. */
data class BrowseEntry(
    val key: String,
    val title: String,
    val fileName: String,
    val collection: String,
    val sourceId: String?,
    val sourceName: String,
    val isFileSource: Boolean,
    /** Recording date for home videos, release year for films and shows, otherwise null. Never a copy date. */
    val date: Instant?,
    val addedAt: Instant,
    val duration: Double?,
    val progressFraction: Double,
    val isFinished: Boolean,
    val kind: ContentKind = ContentKind.HOME_VIDEO,
    val show: String? = null,
    val season: Int? = null,
    val episode: Int? = null,
    val franchise: String? = null,
    val isUHD: Boolean = false,
    val lastPlayedAt: Instant? = null,
)

enum class LibrarySort(val title: String) {
    RECORDED("Date Recorded"), ADDED("Date Added"), TITLE("Title"), LENGTH("Length"),
}

enum class LibraryFilter(val title: String) {
    ALL("All Videos"), UNWATCHED("Unwatched"), IN_PROGRESS("In Progress"), WATCHED("Watched"),
}

object LibraryQuery {
    /** Keys in display order. Newest, longest or A–Z first unless [ascending] flips it. */
    fun apply(
        entries: List<BrowseEntry>, sort: LibrarySort, ascending: Boolean = false, filter: LibraryFilter = LibraryFilter.ALL,
        search: String = "", zone: ZoneId = ZoneId.systemDefault(), locale: Locale = Locale.getDefault(),
    ): List<String> {
        val words = search.split(' ').filter { it.isNotEmpty() }.map(::fold)
        val matching = entries.filter { entry ->
            val keep = when (filter) {
                LibraryFilter.ALL -> true
                LibraryFilter.UNWATCHED -> !entry.isFinished && entry.progressFraction <= 0.02
                LibraryFilter.IN_PROGRESS -> !entry.isFinished && entry.progressFraction > 0.02
                LibraryFilter.WATCHED -> entry.isFinished
            }
            if (!keep) return@filter false
            if (words.isEmpty()) return@filter true
            val haystack = fold(searchableText(entry, zone, locale))
            words.all { haystack.contains(it) }
        }
        // Title order puts A first, so its natural direction is the opposite of the others.
        val comparator: Comparator<BrowseEntry> = when (sort) {
            LibrarySort.RECORDED -> compareByDescending<BrowseEntry> { it.date ?: Instant.MIN }.thenByDescending { it.key }
            LibrarySort.ADDED -> compareByDescending<BrowseEntry> { it.addedAt }.thenByDescending { it.key }
            LibrarySort.LENGTH -> compareByDescending<BrowseEntry> { it.duration ?: 0.0 }.thenByDescending { it.key }
            LibrarySort.TITLE -> Comparator<BrowseEntry> { a, b -> NaturalOrder.compare(a.title, b.title) }.thenBy { it.key }
        }
        val sorted = matching.sortedWith(comparator)
        return (if (ascending) sorted.reversed() else sorted).map { it.key }
    }

    /** Title, file name, folder, library, plus the year and month it was shot ("2019", "July"). */
    fun searchableText(entry: BrowseEntry, zone: ZoneId = ZoneId.systemDefault(), locale: Locale = Locale.getDefault()): String {
        val parts = mutableListOf(entry.title, entry.fileName, entry.collection, entry.sourceName)
        entry.date?.atZone(zone)?.let {
            parts += it.year.toString()
            parts += it.month.getDisplayName(TextStyle.FULL, locale)
        }
        return parts.joinToString(" ")
    }

    /** Lowercased with accents removed, so "alesund" finds "Ålesund". */
    private fun fold(text: String): String =
        Normalizer.normalize(text, Normalizer.Form.NFD).replace(Regex("""\p{Mn}+"""), "").lowercase(Locale.ROOT)
}

/** A collection card: a top-level folder, the loose videos at a folder's root, or individually added videos. */
data class CollectionGroup(
    val id: String,
    val title: String,
    /** Library name, shown when two folders in different libraries share a name. */
    val detail: String?,
    val itemKeys: List<String>,
    val coverKey: String?,
    val years: IntRange?,
)

object CollectionBuilder {
    const val SINGLE_VIDEOS_ID = "single-videos"

    fun build(entries: List<BrowseEntry>, zone: ZoneId = ZoneId.systemDefault()): List<CollectionGroup> {
        val grouped = entries.groupBy { entry ->
            if (entry.isFileSource) SINGLE_VIDEOS_ID
            else {
                val source = entry.sourceId ?: "?"
                if (entry.collection.isEmpty()) "$source/" else "$source/${entry.collection}"
            }
        }
        val groups = grouped.map { (id, members) ->
            val newestFirst = members.sortedWith(compareByDescending<BrowseEntry> { it.date ?: Instant.MIN }.thenByDescending { it.key })
            val first = members[0]
            val title = when {
                id == SINGLE_VIDEOS_ID -> "Individual Videos"
                first.collection.isEmpty() -> first.sourceName
                else -> first.collection
            }
            val years = members.mapNotNull { it.date?.atZone(zone)?.year }
            CollectionGroup(
                id = id, title = title, detail = if (first.collection.isEmpty()) null else first.sourceName,
                itemKeys = newestFirst.map { it.key }, coverKey = newestFirst.firstOrNull()?.key,
                years = if (years.isEmpty()) null else years.min()..years.max(),
            )
        }
        // The library name only helps when two cards would otherwise look the same.
        val titleCounts = groups.groupingBy { it.title }.eachCount()
        return groups
            .map { if ((titleCounts[it.title] ?: 0) < 2) it.copy(detail = null) else it }
            .sortedWith(
                compareBy<CollectionGroup> { it.id == SINGLE_VIDEOS_ID }
                    .then { a, b -> NaturalOrder.compare(a.title, b.title) }
                    .thenBy { it.id },
            )
    }

    fun subtitle(group: CollectionGroup): String {
        val count = group.itemKeys.size
        val parts = mutableListOf("$count video${if (count == 1) "" else "s"}")
        group.years?.let { parts += if (it.first == it.last) "${it.first}" else "${it.first}–${it.last}" }
        group.detail?.let { parts += it }
        return parts.joinToString(" · ")
    }
}
