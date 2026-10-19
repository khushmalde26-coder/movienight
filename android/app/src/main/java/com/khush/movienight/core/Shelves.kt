package com.khush.movienight.core

import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
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

/** A value snapshot of any video, for the Films, TV Shows and Home pages. */
data class BrowseEntry(
    val key: String,
    val title: String,
    val collection: String = "",
    val date: Instant? = null,
    val addedAt: Instant,
    val duration: Double? = null,
    val progressFraction: Double = 0.0,
    val isFinished: Boolean = false,
    val kind: ContentKind = ContentKind.HOME_VIDEO,
    val show: String? = null,
    val season: Int? = null,
    val episode: Int? = null,
    val franchise: String? = null,
    val isUHD: Boolean = false,
    val lastPlayedAt: Instant? = null,
    // From TitleChek, films only.
    val genres: List<String> = emptyList(),
    val directors: List<String> = emptyList(),
    val tmdbCollection: String? = null,
    val year: Int? = null,
) {
    val isInProgress: Boolean get() = !isFinished && progressFraction > 0.02 && lastPlayedAt != null
}

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
    data object Uhd : ShelfKind
    data object Epics : ShelfKind
    data class Franchise(val name: String) : ShelfKind
    // Films rows from TitleChek.
    data class TmdbCollection(val name: String) : ShelfKind
    data class Genre(val name: String) : ShelfKind
    data class Decade(val decade: Int) : ShelfKind
    data class Director(val name: String) : ShelfKind
}

data class Shelf(val kind: ShelfKind, val title: String, val itemKeys: List<String>) {
    val id: String get() = kind.toString()
}

private val RECENT_WINDOW: Duration = Duration.ofDays(30)

private fun isRecent(addedAt: Instant, now: Instant) = Duration.between(addedAt, now) < RECENT_WINDOW

/** Day number that changes at local midnight, for rows and banners that rotate daily. */
private fun dayNumber(now: Instant, zone: ZoneId) = now.atZone(zone).toLocalDate().toEpochDay()

object ShelfBuilder {
    /** Films, full recitals, a whole wedding: long enough to sit down for. */
    const val LONG_VIDEO_MINIMUM = 40 * 60.0
    const val QUICK_CLIP_MAXIMUM = 60.0
    const val ON_THIS_DAY_TOLERANCE_DAYS = 3

    fun build(items: List<ShelfInput>, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): List<Shelf> {
        val shelves = mutableListOf<Shelf>()
        val newestFirst = compareByDescending<ShelfInput> { it.date ?: Instant.MIN }

        val inProgress = items.filter { !it.isFinished && it.progressFraction > 0.02 && it.lastPlayedAt != null }
            .sortedByDescending { it.lastPlayedAt }
        if (inProgress.isNotEmpty()) shelves += Shelf(ShelfKind.ContinueWatching, "Continue Watching", inProgress.take(20).map { it.key })

        val memories = onThisDay(items, now, zone)
        if (memories.isNotEmpty()) shelves += Shelf(ShelfKind.OnThisDay, "On This Day", memories.map { it.key })

        // On first import everything is "recent", which would just duplicate the library.
        val recent = items.filter { isRecent(it.addedAt, now) }.sortedByDescending { it.addedAt }
        if (recent.isNotEmpty() && recent.size < items.size) shelves += Shelf(ShelfKind.RecentlyAdded, "Recently Added", recent.take(30).map { it.key })

        // Duration-based rows only appear when they say something the rest of the page doesn't.
        val long = items.filter { (it.duration ?: 0.0) >= LONG_VIDEO_MINIMUM }.sortedWith(newestFirst)
        if (long.size >= 2 && long.size < items.size) shelves += Shelf(ShelfKind.LongVideos, "Feature Length", long.map { it.key })

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
        if (quick.size >= 3 && quick.size < items.size) shelves += Shelf(ShelfKind.QuickClips, "Quick Clips", quick.take(40).map { it.key })

        val undated = items.filter { it.date == null }
        if (undated.isNotEmpty()) shelves += Shelf(ShelfKind.Undated, "Undated", undated.sortedByDescending { it.addedAt }.map { it.key })
        return shelves
    }

    /** Clips shot within a few days of today's date in earlier years, newest year first. */
    fun onThisDay(items: List<ShelfInput>, now: Instant, zone: ZoneId): List<ShelfInput> {
        val today = now.atZone(zone).toLocalDate()
        return items.filter { item ->
            val date = item.date?.atZone(zone)?.toLocalDate() ?: return@filter false
            if (date.year >= today.year) return@filter false
            // 29 February in a year without one lands on 1 March, as on the Apple app.
            val anchor = runCatching { LocalDate.of(date.year, today.month, today.dayOfMonth) }.getOrElse { LocalDate.of(date.year, 3, 1) }
            abs(ChronoUnit.DAYS.between(anchor, date)) <= ON_THIS_DAY_TOLERANCE_DAYS
        }.sortedByDescending { it.date }
    }
}

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

private val episodeOrder = compareBy<BrowseEntry>({ it.season ?: 1 }, { it.episode ?: 0 }, { it.key })

object TVLibrary {
    fun shows(entries: List<BrowseEntry>): List<TVShowSummary> {
        val byShow = entries.filter { (it.kind == ContentKind.EPISODE || it.kind == ContentKind.EXTRA) && it.show != null }.groupBy { it.show!! }
        return byShow.mapNotNull { (name, members) ->
            val episodes = members.filter { it.kind == ContentKind.EPISODE }.sortedWith(episodeOrder)
            if (episodes.isEmpty()) return@mapNotNull null
            TVShowSummary(
                name = name,
                episodeKeys = episodes.map { it.key },
                seasons = episodes.map { it.season ?: 1 }.distinct().sorted(),
                extraKeys = members.filter { it.kind == ContentKind.EXTRA }.sortedWith(compareBy(NaturalOrder) { it.title }).map { it.key },
                nextKey = nextEpisode(episodes),
                lastPlayedAt = episodes.mapNotNull { it.lastPlayedAt }.maxOrNull(),
                latestAddedAt = episodes.maxOf { it.addedAt },
            )
        }.sortedWith(compareBy(NaturalOrder) { it.name })
    }

    /**
     * Partway through one? That one. Otherwise the first unfinished episode after the last one you
     * watched; a show you've never started begins at the first episode.
     */
    fun nextEpisode(episodes: List<BrowseEntry>): String? {
        episodes.filter { it.isInProgress }.maxByOrNull { it.lastPlayedAt!! }?.let { return it.key }
        val lastWatched = episodes.indexOfLast { it.isFinished || it.lastPlayedAt != null }
        return episodes.drop(lastWatched + 1).firstOrNull { !it.isFinished }?.key
    }
}

object FilmShelves {
    const val EPIC_MINIMUM = 150 * 60.0
    const val GENRE_MINIMUM = 3
    const val MAXIMUM_GENRE_ROWS = 6
    const val DECADE_MINIMUM = 3
    const val DIRECTOR_MINIMUM = 2

    /** Films in release order when every one has a year, otherwise by title ("Rocky", "Rocky II"). */
    fun ordered(films: List<BrowseEntry>): List<BrowseEntry> =
        if (films.all { it.date != null }) films.sortedWith(compareBy({ it.date }, { it.key }))
        else films.sortedWith(compareBy(NaturalOrder) { it.title })

    fun build(entries: List<BrowseEntry>, now: Instant = Instant.now()): List<Shelf> {
        val films = entries.filter { it.kind == ContentKind.FILM }
        if (films.isEmpty()) return emptyList()
        val shelves = mutableListOf<Shelf>()

        val recent = films.filter { isRecent(it.addedAt, now) }.sortedByDescending { it.addedAt }
        if (recent.isNotEmpty() && recent.size < films.size) shelves += Shelf(ShelfKind.RecentlyAdded, "Recently Added", recent.take(30).map { it.key })
        val unwatched = films.filter { !it.isFinished && it.progressFraction <= 0.02 }
        if (unwatched.isNotEmpty() && unwatched.size < films.size) shelves += Shelf(ShelfKind.Unwatched, "Unwatched", ordered(unwatched).map { it.key })
        val franchises = films.filter { it.franchise != null }.groupBy { it.franchise!! }
        for (name in franchises.keys.sortedWith(NaturalOrder)) {
            shelves += Shelf(ShelfKind.Franchise(name), name, ordered(franchises.getValue(name)).map { it.key })
        }
        shelves += matchedShelves(films, franchises)
        val uhd = films.filter { it.isUHD }
        if (uhd.size >= 2 && uhd.size < films.size) shelves += Shelf(ShelfKind.Uhd, "In 4K", ordered(uhd).map { it.key })
        val epics = films.filter { (it.duration ?: 0.0) >= EPIC_MINIMUM }.sortedByDescending { it.duration ?: 0.0 }
        if (epics.size >= 2 && epics.size < films.size) shelves += Shelf(ShelfKind.Epics, "Epics", epics.map { it.key })
        return shelves
    }

    /**
     * Rows that need TitleChek data (decades also use years from file names): TMDB's collections
     * that no folder already groups, the biggest genres, decades and directors with a few films each.
     */
    fun matchedShelves(films: List<BrowseEntry>, franchises: Map<String, List<BrowseEntry>>): List<Shelf> {
        val shelves = mutableListOf<Shelf>()
        val folderSets = franchises.values.map { group -> group.map { it.key }.toSet() }.toSet()
        val folderNames = franchises.keys.map(TitleMatcher::normalize).toSet()
        val collections = films.filter { it.tmdbCollection != null }.groupBy { it.tmdbCollection!! }
        for (name in collections.keys.sortedWith(NaturalOrder)) {
            val members = collections.getValue(name)
            val shortName = name.replace(Regex("""\s+Collection$"""), "")
            if (members.size < 2 || members.map { it.key }.toSet() in folderSets || TitleMatcher.normalize(shortName) in folderNames) continue
            shelves += Shelf(ShelfKind.TmdbCollection(name), name, ordered(members).map { it.key })
        }

        val byGenre = mutableMapOf<String, MutableList<BrowseEntry>>()
        for (film in films) for (genre in film.genres) byGenre.getOrPut(genre) { mutableListOf() } += film
        val genres = byGenre.filter { it.value.size >= GENRE_MINIMUM && it.value.size < films.size }.entries
            .sortedWith(compareByDescending<Map.Entry<String, MutableList<BrowseEntry>>> { it.value.size }.thenBy { it.key })
            .take(MAXIMUM_GENRE_ROWS)
        for ((genre, members) in genres) {
            shelves += Shelf(ShelfKind.Genre(genre), genre, members.sortedWith(compareByDescending<BrowseEntry> { it.year ?: 0 }.thenByDescending { it.key }).map { it.key })
        }

        val decades = films.filter { it.year != null }.groupBy { it.year!! / 10 * 10 }.filter { it.value.size >= DECADE_MINIMUM }
        if (decades.size >= 2) {
            for (decade in decades.keys.sortedDescending()) {
                shelves += Shelf(ShelfKind.Decade(decade), "The ${decade}s", ordered(decades.getValue(decade)).map { it.key })
            }
        }

        val byDirector = mutableMapOf<String, MutableList<BrowseEntry>>()
        for (film in films) for (director in film.directors) byDirector.getOrPut(director) { mutableListOf() } += film
        for (director in byDirector.keys.sortedWith(NaturalOrder)) {
            val members = byDirector.getValue(director)
            if (members.size >= DIRECTOR_MINIMUM) shelves += Shelf(ShelfKind.Director(director), "Directed by $director", ordered(members).map { it.key })
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
        val watching = entries.filter { it.kind != ContentKind.EPISODE && it.kind != ContentKind.EXTRA && it.isInProgress }
            .sortedByDescending { it.lastPlayedAt }
        if (watching.isNotEmpty()) shelves += Shelf(ShelfKind.ContinueWatching, "Continue Watching", watching.take(20).map { it.key })
        val next = TVLibrary.shows(entries).filter { it.lastPlayedAt != null && it.nextKey != null }.sortedByDescending { it.lastPlayedAt }
        if (next.isNotEmpty()) shelves += Shelf(ShelfKind.NextUp, "Next Up", next.mapNotNull { it.nextKey })

        // New things, with a show's batch of new episodes counted once: its earliest new episode,
        // placed where the show's newest arrival would be.
        val fresh = entries.filter { it.kind != ContentKind.EXTRA && isRecent(it.addedAt, now) }
        val newEpisodes = fresh.filter { it.kind == ContentKind.EPISODE && it.show != null }.groupBy { it.show!! }
        val showCards = newEpisodes.values.map { episodes ->
            val first = episodes.minWith(compareBy({ it.season ?: 1 }, { it.episode ?: 0 }))
            first to episodes.maxOf { it.addedAt }
        }
        val others = fresh.filter { !(it.kind == ContentKind.EPISODE && it.show != null) }.map { it to it.addedAt }
        val recent = (others + showCards).sortedWith(compareByDescending<Pair<BrowseEntry, Instant>> { it.second }.thenByDescending { it.first.key }).map { it.first }
        val mainCount = entries.count { it.kind != ContentKind.EXTRA }
        if (recent.isNotEmpty() && recent.size < mainCount) shelves += Shelf(ShelfKind.RecentlyAdded, "Recently Added", recent.take(30).map { it.key })

        // Rotating highlights: today's memories always lead; the rest take turns day by day.
        val candidates = FilmShelves.build(entries, now).filter { it.kind != ShelfKind.RecentlyAdded }.toMutableList()
        val homeShelves = ShelfBuilder.build(homeVideos, now, zone)
        homeShelves.firstOrNull { it.kind == ShelfKind.OnThisDay }?.let { shelves += it }
        homeShelves.firstOrNull { it.kind is ShelfKind.Year }?.let { candidates += Shelf(it.kind, "Home Videos from ${it.title}", it.itemKeys) }
        if (candidates.isNotEmpty()) {
            val start = (dayNumber(now, zone) % candidates.size).toInt()
            val rotated = candidates.drop(start) + candidates.take(start)
            shelves += rotated.take(highlights).map { Shelf(it.kind, it.title, it.itemKeys.take(20)) }
        }
        return shelves
    }

    /** The banner: a memory from this date, else a film that changes daily, else anything. */
    fun heroKey(entries: List<BrowseEntry>, homeVideos: List<ShelfInput>, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): String? {
        ShelfBuilder.onThisDay(homeVideos.filter { !it.isVertical }, now, zone).firstOrNull()?.let { return it.key }
        val films = entries.filter { it.kind == ContentKind.FILM }.map { it.key }.sorted()
        val pool = films.ifEmpty { entries.filter { it.kind != ContentKind.EXTRA }.map { it.key }.sorted() }
        if (pool.isEmpty()) return null
        return pool[(dayNumber(now, zone) % pool.size).toInt()]
    }

    /** Home videos' banner on their own page: today's memory, else a landscape clip that changes daily. */
    fun homeVideoHero(items: List<ShelfInput>, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): String? {
        val landscape = items.filter { !it.isVertical }
        val pool = landscape.ifEmpty { items }
        ShelfBuilder.onThisDay(pool, now, zone).firstOrNull()?.let { return it.key }
        val candidates = pool.filter { it.date != null }.map { it.key }.sorted()
        if (candidates.isEmpty()) return pool.map { it.key }.sorted().firstOrNull()
        return candidates[(dayNumber(now, zone) % candidates.size).toInt()]
    }
}

/** 1 January of a release year, for sorting films by year like dated videos. */
fun yearInstant(year: Int): Instant = LocalDate.of(year, 1, 1).atStartOfDay().toInstant(ZoneOffset.UTC)
