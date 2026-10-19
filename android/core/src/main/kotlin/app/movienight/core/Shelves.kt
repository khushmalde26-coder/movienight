package app.movienight.core

import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import kotlin.math.abs

/** A value snapshot of a home video, so shelf logic is pure and testable. */
data class ShelfInput(
    val key: String,
    val collection: String,
    val date: Instant?,
    val addedAt: Instant,
    val progressFraction: Double,
    val duration: Double? = null,
    val isVertical: Boolean = false,
    val lastPlayedAt: Instant? = null,
    val isFinished: Boolean,
)

sealed interface ShelfKind {
    data object ContinueWatching : ShelfKind
    data object OnThisDay : ShelfKind
    data object RecentlyAdded : ShelfKind
    data object LongVideos : ShelfKind
    data object QuickClips : ShelfKind
    data class Collection(val name: String) : ShelfKind
    data class Year(val year: Int) : ShelfKind
    data object Undated : ShelfKind
    data object NextUp : ShelfKind
    data object Unwatched : ShelfKind
    data object UHD : ShelfKind
    data object Epics : ShelfKind
    data class Franchise(val name: String) : ShelfKind
}

data class Shelf(val kind: ShelfKind, val title: String, val itemKeys: List<String>)

/** The date-based rows built for camera footage, used by the Home Videos section. */
object ShelfBuilder {
    val recentlyAddedWindow: Duration = Duration.ofDays(30)
    const val ON_THIS_DAY_TOLERANCE_DAYS = 3
    /** Films, full recitals, a whole wedding: long enough to sit down for. */
    const val LONG_VIDEO_MINIMUM = 40.0 * 60
    const val QUICK_CLIP_MAXIMUM = 60.0

    private val newestFirst = compareByDescending<ShelfInput> { it.date ?: Instant.MIN }

    fun build(items: List<ShelfInput>, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): List<Shelf> {
        val shelves = mutableListOf<Shelf>()

        val inProgress = items.filter { !it.isFinished && it.progressFraction > 0.02 && it.lastPlayedAt != null }
            .sortedByDescending { it.lastPlayedAt }
        if (inProgress.isNotEmpty()) {
            shelves += Shelf(ShelfKind.ContinueWatching, "Continue Watching", inProgress.take(20).map { it.key })
        }

        val memories = onThisDay(items, now, zone)
        if (memories.isNotEmpty()) shelves += Shelf(ShelfKind.OnThisDay, "On This Day", memories.map { it.key })

        // On first import everything is "recent", which would just duplicate the library.
        val recent = items.filter { Duration.between(it.addedAt, now) < recentlyAddedWindow }.sortedByDescending { it.addedAt }
        if (recent.isNotEmpty() && recent.size < items.size) {
            shelves += Shelf(ShelfKind.RecentlyAdded, "Recently Added", recent.take(30).map { it.key })
        }

        // Duration-based rows only appear when they say something the rest of the page doesn't.
        val long = items.filter { (it.duration ?: 0.0) >= LONG_VIDEO_MINIMUM }.sortedWith(newestFirst)
        if (long.size >= 2 && long.size < items.size) {
            shelves += Shelf(ShelfKind.LongVideos, "Feature Length", long.map { it.key })
        }

        val byCollection = items.filter { it.collection.isNotEmpty() }.groupBy { it.collection }
        for (name in byCollection.keys.sortedWith(NaturalOrder)) {
            val group = byCollection.getValue(name)
            // A folder holding the whole library is not a useful shelf.
            if (group.size >= items.size) continue
            shelves += Shelf(ShelfKind.Collection(name), name, group.sortedWith(newestFirst).map { it.key })
        }

        val byYear = items.filter { it.date != null }.groupBy { it.date!!.atZone(zone).year }
        for (year in byYear.keys.sortedDescending()) {
            shelves += Shelf(ShelfKind.Year(year), year.toString(), byYear.getValue(year).sortedWith(newestFirst).map { it.key })
        }

        val quick = items.filter { (it.duration ?: Double.POSITIVE_INFINITY) < QUICK_CLIP_MAXIMUM }.sortedWith(newestFirst)
        if (quick.size >= 3 && quick.size < items.size) {
            shelves += Shelf(ShelfKind.QuickClips, "Quick Clips", quick.take(40).map { it.key })
        }

        val undated = items.filter { it.date == null }
        if (undated.isNotEmpty()) {
            shelves += Shelf(ShelfKind.Undated, "Undated", undated.sortedByDescending { it.addedAt }.map { it.key })
        }
        return shelves
    }

    /** Clips shot within a few days of today's date in earlier years, newest year first. */
    fun onThisDay(items: List<ShelfInput>, now: Instant, zone: ZoneId): List<ShelfInput> {
        val today = now.atZone(zone).toLocalDate()
        return items.filter { item ->
            val date = item.date?.atZone(zone)?.toLocalDate() ?: return@filter false
            if (date.year >= today.year) return@filter false
            // Feb 29 in a year without one falls back to Feb 28, like Calendar does.
            val anchor = LocalDate.of(date.year, today.month, minOf(today.dayOfMonth, today.month.length(date.isLeapYear)))
            abs(ChronoUnit.DAYS.between(anchor, date)) <= ON_THIS_DAY_TOLERANCE_DAYS
        }.sortedByDescending { it.date }
    }

    /**
     * The hero banner: a memory from this date if there is one, otherwise a pick that changes daily.
     * Landscape clips win when there are any, because a vertical video in a wide banner is mostly crop.
     */
    fun heroKey(items: List<ShelfInput>, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): String? {
        val landscape = items.filter { !it.isVertical }
        val pool = landscape.ifEmpty { items }
        onThisDay(pool, now, zone).firstOrNull()?.let { return it.key }
        val candidates = pool.filter { it.date != null }.map { it.key }.sorted()
        if (candidates.isEmpty()) return pool.map { it.key }.sorted().firstOrNull()
        return candidates[Math.floorMod(dayNumber(now, zone), candidates.size)]
    }

    /** Days since the epoch, for picks that change once a day. */
    internal fun dayNumber(now: Instant, zone: ZoneId): Long = now.atZone(zone).toLocalDate().toEpochDay()
}
