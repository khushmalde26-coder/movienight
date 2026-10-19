package app.movienight.core

import java.time.Duration
import java.time.Instant
import java.time.ZoneId

/** A TV show built from its episode files: seasons in order, extras apart, and where you're up to. */
data class TVShowSummary(
    val name: String,
    /** Episodes in watching order (season, then episode). */
    val episodeKeys: List<String>,
    val seasons: List<Int>,
    val extraKeys: List<String>,
    /** The episode to play next: the one you're partway through, or the one after the last you finished. */
    val nextKey: String?,
    /** When anything in the show was last played; null if never. */
    val lastPlayedAt: Instant?,
    val latestAddedAt: Instant,
)

object TVLibrary {
    private val watchingOrder = compareBy<BrowseEntry>({ it.season ?: 1 }, { it.episode ?: 0 }, { it.key })

    fun shows(entries: List<BrowseEntry>): List<TVShowSummary> =
        entries.filter { (it.kind == ContentKind.EPISODE || it.kind == ContentKind.EXTRA) && it.show != null }
            .groupBy { it.show!! }
            .mapNotNull { (name, members) ->
                val episodes = members.filter { it.kind == ContentKind.EPISODE }.sortedWith(watchingOrder)
                if (episodes.isEmpty()) return@mapNotNull null
                TVShowSummary(
                    name = name,
                    episodeKeys = episodes.map { it.key },
                    seasons = episodes.map { it.season ?: 1 }.distinct().sorted(),
                    extraKeys = members.filter { it.kind == ContentKind.EXTRA }
                        .sortedWith { a, b -> NaturalOrder.compare(a.title, b.title) }.map { it.key },
                    nextKey = nextEpisode(episodes),
                    lastPlayedAt = episodes.mapNotNull { it.lastPlayedAt }.maxOrNull(),
                    latestAddedAt = episodes.maxOf { it.addedAt },
                )
            }
            .sortedWith { a, b -> NaturalOrder.compare(a.name, b.name) }

    /**
     * Partway through one? That one. Otherwise the first unfinished episode after the last one you
     * watched; a show you've never started begins at the first episode. [episodes] are in watching order.
     */
    fun nextEpisode(episodes: List<BrowseEntry>): String? {
        episodes.filter { !it.isFinished && it.progressFraction > 0.02 && it.lastPlayedAt != null }
            .maxByOrNull { it.lastPlayedAt!! }
            ?.let { return it.key }
        val lastWatched = episodes.indexOfLast { it.isFinished || it.lastPlayedAt != null }
        return episodes.drop(lastWatched + 1).firstOrNull { !it.isFinished }?.key
    }
}

object FilmShelves {
    const val EPIC_MINIMUM = 150.0 * 60

    /** Films in release order when every one has a year, otherwise by title ("Rocky", "Rocky II"). */
    fun ordered(films: List<BrowseEntry>): List<BrowseEntry> =
        if (films.all { it.date != null }) films.sortedWith(compareBy<BrowseEntry>({ it.date }, { it.key }))
        else films.sortedWith { a, b -> NaturalOrder.compare(a.title, b.title) }

    fun build(entries: List<BrowseEntry>, now: Instant = Instant.now()): List<Shelf> {
        val films = entries.filter { it.kind == ContentKind.FILM }
        if (films.isEmpty()) return emptyList()
        val shelves = mutableListOf<Shelf>()

        val recent = films.filter { Duration.between(it.addedAt, now) < ShelfBuilder.recentlyAddedWindow }.sortedByDescending { it.addedAt }
        if (recent.isNotEmpty() && recent.size < films.size) {
            shelves += Shelf(ShelfKind.RecentlyAdded, "Recently Added", recent.take(30).map { it.key })
        }
        val unwatched = films.filter { !it.isFinished && it.progressFraction <= 0.02 }
        if (unwatched.isNotEmpty() && unwatched.size < films.size) {
            shelves += Shelf(ShelfKind.Unwatched, "Unwatched", ordered(unwatched).map { it.key })
        }
        val franchises = films.filter { it.franchise != null }.groupBy { it.franchise!! }
        for (name in franchises.keys.sortedWith(NaturalOrder)) {
            shelves += Shelf(ShelfKind.Franchise(name), name, ordered(franchises.getValue(name)).map { it.key })
        }
        val uhd = films.filter { it.isUHD }
        if (uhd.size >= 2 && uhd.size < films.size) {
            shelves += Shelf(ShelfKind.UHD, "In 4K", ordered(uhd).map { it.key })
        }
        val epics = films.filter { (it.duration ?: 0.0) >= EPIC_MINIMUM }.sortedByDescending { it.duration ?: 0.0 }
        if (epics.size >= 2 && epics.size < films.size) {
            shelves += Shelf(ShelfKind.Epics, "Epics", epics.map { it.key })
        }
        return shelves
    }
}

/** The mixed front page: what you're in the middle of, what's next, what's new, then a few rows that change daily. */
object HomeShelves {
    fun build(
        entries: List<BrowseEntry>, homeVideos: List<ShelfInput>, now: Instant = Instant.now(),
        zone: ZoneId = ZoneId.systemDefault(), highlights: Int = 4,
    ): List<Shelf> {
        val shelves = mutableListOf<Shelf>()
        // Episodes go in Next Up instead, one per show.
        val watching = entries
            .filter { it.kind != ContentKind.EPISODE && it.kind != ContentKind.EXTRA && !it.isFinished && it.progressFraction > 0.02 && it.lastPlayedAt != null }
            .sortedByDescending { it.lastPlayedAt }
        if (watching.isNotEmpty()) {
            shelves += Shelf(ShelfKind.ContinueWatching, "Continue Watching", watching.take(20).map { it.key })
        }
        val next = TVLibrary.shows(entries).filter { it.lastPlayedAt != null && it.nextKey != null }.sortedByDescending { it.lastPlayedAt }
        if (next.isNotEmpty()) shelves += Shelf(ShelfKind.NextUp, "Next Up", next.mapNotNull { it.nextKey })

        // New things, with a show's batch of new episodes counted once: its earliest new episode,
        // placed where the show's newest arrival would be.
        val fresh = entries.filter { it.kind != ContentKind.EXTRA && Duration.between(it.addedAt, now) < ShelfBuilder.recentlyAddedWindow }
        val newEpisodes = fresh.filter { it.kind == ContentKind.EPISODE && it.show != null }.groupBy { it.show!! }
        val showCards = newEpisodes.values.map { episodes ->
            episodes.minWith(compareBy({ it.season ?: 1 }, { it.episode ?: 0 })) to episodes.maxOf { it.addedAt }
        }
        val others = fresh.filter { !(it.kind == ContentKind.EPISODE && it.show != null) }.map { it to it.addedAt }
        val recent = (others + showCards)
            .sortedWith(compareByDescending<Pair<BrowseEntry, Instant>> { it.second }.thenByDescending { it.first.key })
            .map { it.first }
        val mainCount = entries.count { it.kind != ContentKind.EXTRA }
        if (recent.isNotEmpty() && recent.size < mainCount) {
            shelves += Shelf(ShelfKind.RecentlyAdded, "Recently Added", recent.take(30).map { it.key })
        }

        // Rotating highlights: today's memories always lead; the rest take turns day by day.
        val candidates = FilmShelves.build(entries, now).filter { it.kind != ShelfKind.RecentlyAdded }.toMutableList()
        val homeShelves = ShelfBuilder.build(homeVideos, now, zone)
        homeShelves.firstOrNull { it.kind == ShelfKind.OnThisDay }?.let { shelves += it }
        homeShelves.firstOrNull { it.kind is ShelfKind.Year }?.let {
            candidates += Shelf(it.kind, "Home Videos from ${it.title}", it.itemKeys)
        }
        if (candidates.isNotEmpty()) {
            val start = Math.floorMod(ShelfBuilder.dayNumber(now, zone), candidates.size)
            val rotated = candidates.drop(start) + candidates.take(start)
            shelves += rotated.take(highlights).map { it.copy(itemKeys = it.itemKeys.take(20)) }
        }
        return shelves
    }

    /** The banner: a memory from this date, else a film that changes daily, else anything. */
    fun heroKey(entries: List<BrowseEntry>, homeVideos: List<ShelfInput>, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): String? {
        ShelfBuilder.onThisDay(homeVideos.filter { !it.isVertical }, now, zone).firstOrNull()?.let { return it.key }
        val films = entries.filter { it.kind == ContentKind.FILM }.map { it.key }.sorted()
        val pool = films.ifEmpty { entries.filter { it.kind != ContentKind.EXTRA }.map { it.key }.sorted() }
        if (pool.isEmpty()) return null
        return pool[Math.floorMod(ShelfBuilder.dayNumber(now, zone), pool.size)]
    }
}
