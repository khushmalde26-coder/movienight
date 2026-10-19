package app.movienight.core

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

private val utc = ZoneOffset.UTC
private fun day(text: String): Instant = LocalDate.parse(text).atTime(12, 0).toInstant(utc)
private fun yearStart(year: Int): Instant = LocalDate.of(year, 1, 1).atStartOfDay().toInstant(utc)

class HomeVideoShelfTest {
    private fun item(key: String, date: String?, collection: String = "", added: String = "2026-01-01",
                     progress: Double = 0.0, played: String? = null, finished: Boolean = false, duration: Double? = null,
                     vertical: Boolean = false) =
        ShelfInput(key, collection, date?.let(::day), day(added), progress, duration, vertical, played?.let(::day), finished)

    private val now = day("2026-10-19")

    @Test fun groupsByYearNewestFirst() {
        val shelves = ShelfBuilder.build(listOf(item("a", "2019-03-01"), item("b", "2021-05-01"), item("c", "2019-08-01")), now, utc)
        val years = shelves.filter { it.kind is ShelfKind.Year }
        assertEquals(listOf("2021", "2019"), years.map { it.title })
        assertEquals(listOf("c", "a"), years.last().itemKeys)
    }

    @Test fun continueWatchingSkipsFinishedAndUntouched() {
        val shelves = ShelfBuilder.build(listOf(
            item("half", null, progress = 0.5, played = "2026-10-18"),
            item("done", null, progress = 0.5, played = "2026-10-18", finished = true),
            item("fresh", null),
        ), now, utc)
        assertEquals(ShelfKind.ContinueWatching, shelves.first().kind)
        assertEquals(listOf("half"), shelves.first().itemKeys)
    }

    @Test fun onThisDayUsesEarlierYearsWithinTolerance() {
        val items = listOf(item("hit", "2018-10-17"), item("miss", "2018-11-19"), item("thisYear", "2026-10-19"))
        assertEquals(listOf("hit"), ShelfBuilder.onThisDay(items, now, utc).map { it.key })
        assertEquals("hit", ShelfBuilder.heroKey(items, now, utc))
    }

    @Test fun recentlyAddedHiddenOnFirstImportAndWholeLibraryFoldersSkipped() {
        val shelves = ShelfBuilder.build(listOf(
            item("a", null, collection = "Holidays", added = "2026-10-18"), item("b", null, collection = "Holidays", added = "2026-10-18"),
        ), now, utc)
        assertFalse(shelves.any { it.kind == ShelfKind.RecentlyAdded })
        assertFalse(shelves.any { it.kind == ShelfKind.Collection("Holidays") })
    }

    @Test fun longAndShortRowsAndALandscapeHero() {
        val shelves = ShelfBuilder.build(listOf(
            item("film1", "2025-01-01", duration = 6000.0), item("film2", "2025-01-01", duration = 5400.0),
            item("c1", "2025-01-01", duration = 12.0), item("c2", "2025-01-01", duration = 30.0), item("c3", "2025-01-01", duration = 50.0),
            item("mid", "2025-01-01", duration = 600.0),
        ), now, utc)
        assertEquals(listOf("film1", "film2"), shelves.first { it.kind == ShelfKind.LongVideos }.itemKeys.sorted())
        assertEquals(3, shelves.first { it.kind == ShelfKind.QuickClips }.itemKeys.size)
        val clips = listOf(item("tall1", "2025-01-01", vertical = true), item("wide", "2025-01-01"), item("tall2", "2025-01-01", vertical = true))
        assertEquals("wide", ShelfBuilder.heroKey(clips, now, utc))
    }
}

class SectionShelfTest {
    private val now = Instant.ofEpochSecond(2_000_000_000)

    private fun episode(show: String, season: Int, number: Int, finished: Boolean = false, progress: Double = 0.0,
                        played: Long? = null, added: Long = 0) =
        BrowseEntry("$show-$season-$number", show, "", show, null, "", false, null, now.minusSeconds(added), 3000.0,
            progress, finished, ContentKind.EPISODE, show, season, number, lastPlayedAt = played?.let { now.minusSeconds(it) })

    private fun film(title: String, year: Int? = null, franchise: String? = null, added: Long = 0) =
        BrowseEntry(title, title, title, franchise ?: "", null, "", false, year?.let(::yearStart), now.minusSeconds(added),
            6000.0, 0.0, false, ContentKind.FILM, franchise = franchise)

    @Test fun nextEpisodeFollowsWhereYouAre() {
        assertEquals("S-1-1", TVLibrary.nextEpisode(listOf(episode("S", 1, 1), episode("S", 1, 2))))
        val partway = listOf(episode("S", 1, 1, finished = true, played = 100), episode("S", 1, 2, progress = 0.3, played = 10), episode("S", 1, 3))
        assertEquals("S-1-2", TVLibrary.nextEpisode(partway))
        val between = listOf(episode("S", 1, 1, finished = true, played = 100), episode("S", 1, 2, finished = true, played = 50), episode("S", 2, 1))
        assertEquals("S-2-1", TVLibrary.nextEpisode(between))
        assertNull(TVLibrary.nextEpisode(listOf(episode("S", 1, 1, finished = true, played = 5))))
    }

    @Test fun groupsShowsInWatchingOrder() {
        val shows = TVLibrary.shows(listOf(episode("B", 2, 1), episode("B", 1, 10), episode("B", 1, 2), episode("A", 1, 1)))
        assertEquals(listOf("A", "B"), shows.map { it.name })
        assertEquals(listOf("B-1-2", "B-1-10", "B-2-1"), shows[1].episodeKeys)
        assertEquals(listOf(1, 2), shows[1].seasons)
    }

    @Test fun franchisesInReleaseOrderWhenKnown() {
        val shelves = FilmShelves.build(listOf(
            film("Skyfall", 2012, "007"), film("Dr No", 1962, "007"),
            film("Rocky II", franchise = "Rocky"), film("Rocky", 1976, "Rocky"), film("Inception"),
        ), now)
        assertEquals(listOf("Dr No", "Skyfall"), shelves.first { it.kind == ShelfKind.Franchise("007") }.itemKeys)
        assertEquals(listOf("Rocky", "Rocky II"), shelves.first { it.kind == ShelfKind.Franchise("Rocky") }.itemKeys)
    }

    @Test fun homeCountsANewSeasonOnceAndPutsShowsInNextUp() {
        val days90 = 90L * 86_400
        val entries = listOf(
            episode("Show", 1, 2, added = 10), episode("Show", 1, 1, added = 10), episode("Show", 1, 3, added = 5),
            episode("Other", 1, 1, finished = true, played = 60, added = days90), episode("Other", 1, 2, added = days90),
            film("Old film", added = days90),
        )
        val shelves = HomeShelves.build(entries, emptyList(), now, utc)
        assertEquals(listOf("Other-1-2"), shelves.first { it.kind == ShelfKind.NextUp }.itemKeys)
        assertEquals(listOf("Show-1-1"), shelves.first { it.kind == ShelfKind.RecentlyAdded }.itemKeys)
        assertNull(shelves.firstOrNull { it.kind == ShelfKind.ContinueWatching })     // episodes live in Next Up
    }
}

class LibraryQueryTest {
    private fun entry(key: String, title: String, collection: String = "", year: Int? = null, added: Long = 0,
                      length: Double? = null, progress: Double = 0.0, finished: Boolean = false) =
        BrowseEntry(key, title, key, collection, "lib", "Videos", false,
            year?.let { LocalDate.of(it, 7, 14).atStartOfDay().toInstant(utc) }, Instant.ofEpochSecond(added), length, progress, finished)

    private val sample = listOf(
        entry("a", "Beach day", "Holidays", 2019, 3, 60.0),
        entry("b", "Wedding", year = 2018, added = 1, length = 3600.0, finished = true),
        entry("c", "Ålesund trip", "Holidays", 2022, 2, 600.0, progress = 0.4),
        entry("d", "Undated clip", added = 4),
    )

    private fun query(sort: LibrarySort = LibrarySort.ADDED, ascending: Boolean = false, filter: LibraryFilter = LibraryFilter.ALL, search: String = "") =
        LibraryQuery.apply(sample, sort, ascending, filter, search, utc, java.util.Locale.UK)

    @Test fun sortsEachWay() {
        assertEquals(listOf("c", "a", "b", "d"), query(LibrarySort.RECORDED))          // undated last
        assertEquals(listOf("d", "b", "a", "c"), query(LibrarySort.RECORDED, ascending = true))
        assertEquals(listOf("d", "a", "c", "b"), query(LibrarySort.ADDED))
        assertEquals(listOf("b", "c", "a", "d"), query(LibrarySort.LENGTH))
        assertEquals(listOf("c", "a", "d", "b"), query(LibrarySort.TITLE))             // Å sorts with A
    }

    @Test fun filtersByWatchState() {
        assertEquals(listOf("d", "a"), query(filter = LibraryFilter.UNWATCHED))
        assertEquals(listOf("c"), query(filter = LibraryFilter.IN_PROGRESS))
        assertEquals(listOf("b"), query(filter = LibraryFilter.WATCHED))
    }

    @Test fun searchesTitlesFoldersAndYearsWithoutCaringAboutAccents() {
        assertEquals(setOf("a", "c"), query(search = "holidays").toSet())
        assertEquals(listOf("c"), query(search = "alesund"))
        assertEquals(listOf("b"), query(search = "2018"))
        assertEquals(listOf("a"), query(search = "beach 2019"))
        assertTrue(query(search = "beach 2020").isEmpty())
        assertEquals(setOf("a", "b", "c"), query(search = "july").toSet())
    }

    @Test fun naturalOrderComparesNumbersByValue() {
        assertEquals(listOf("Rocky", "Rocky 2", "Rocky 10"), listOf("Rocky 10", "Rocky", "Rocky 2").sortedWith(NaturalOrder))
    }
}

class WatchHistoryTest {
    private val mb = 1_000_000L
    private val old = Instant.ofEpochSecond(1_000)
    private val new = Instant.ofEpochSecond(2_000)

    @Test fun sameNameDifferentRealSizeIsADifferentVideo() {
        assertNull(WatchHistory.bestMatch(50 * mb, listOf(WatchHistory.Candidate(80 * mb, old))))
    }

    @Test fun sameSizeWinsThenNewest() {
        val candidates = listOf(WatchHistory.Candidate(200, new), WatchHistory.Candidate(50 * mb, old))
        assertEquals(1, WatchHistory.bestMatch(50 * mb, candidates))
        assertEquals(0, WatchHistory.bestMatch(300, candidates))
        assertNull(WatchHistory.bestMatch(50 * mb, emptyList()))
    }
}
