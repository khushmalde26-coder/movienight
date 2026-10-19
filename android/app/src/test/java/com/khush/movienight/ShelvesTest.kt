package com.khush.movienight

import com.khush.movienight.core.BrowseEntry
import com.khush.movienight.core.ContentKind
import com.khush.movienight.core.FilmShelves
import com.khush.movienight.core.HomeShelves
import com.khush.movienight.core.ShelfBuilder
import com.khush.movienight.core.ShelfInput
import com.khush.movienight.core.ShelfKind
import com.khush.movienight.core.TVLibrary
import com.khush.movienight.core.TitleMatcher
import com.khush.movienight.core.WatchHistory
import com.khush.movienight.core.yearInstant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Duration
import java.time.Instant
import java.time.ZoneOffset

class ShelvesTest {
    private val now = Instant.ofEpochSecond(2_000_000_000)

    private fun episode(show: String, season: Int, number: Int, finished: Boolean = false, progress: Double = 0.0,
                        played: Long? = null, added: Long = 0) = BrowseEntry(
        key = "$show-$season-$number", title = show, collection = show, addedAt = now.minusSeconds(added), duration = 3000.0,
        progressFraction = progress, isFinished = finished, kind = ContentKind.EPISODE, show = show, season = season, episode = number,
        lastPlayedAt = played?.let { now.minusSeconds(it) },
    )

    private fun film(title: String, year: Int? = null, franchise: String? = null, added: Long = 0, genres: List<String> = emptyList(),
                     directors: List<String> = emptyList(), collection: String? = null, finished: Boolean = false) = BrowseEntry(
        key = title, title = title, collection = franchise ?: "", date = year?.let(::yearInstant), addedAt = now.minusSeconds(added),
        duration = 6000.0, isFinished = finished, kind = ContentKind.FILM, franchise = franchise, genres = genres, directors = directors,
        tmdbCollection = collection, year = year,
    )

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
        assertEquals(listOf("Rocky", "Rocky II"), shelves.first { it.kind == ShelfKind.Franchise("Rocky") }.itemKeys)   // a year missing: by title
    }

    @Test fun homeCountsANewSeasonOnceAndPutsShowsInNextUp() {
        val entries = listOf(
            episode("Show", 1, 2, added = 10), episode("Show", 1, 1, added = 10), episode("Show", 1, 3, added = 5),
            episode("Other", 1, 1, finished = true, played = 60, added = 90 * 86_400), episode("Other", 1, 2, added = 90 * 86_400),
            film("Old film", added = 90 * 86_400),
        )
        val shelves = HomeShelves.build(entries, emptyList(), now, ZoneOffset.UTC)
        assertEquals(listOf("Other-1-2"), shelves.first { it.kind == ShelfKind.NextUp }.itemKeys)
        assertEquals(listOf("Show-1-1"), shelves.first { it.kind == ShelfKind.RecentlyAdded }.itemKeys)
        assertTrue(shelves.none { it.kind == ShelfKind.ContinueWatching })     // episodes live in Next Up
    }

    @Test fun buildsGenreDecadeDirectorAndCollectionRows() {
        val films = listOf(
            film("Heat", 1995, genres = listOf("Crime", "Drama"), directors = listOf("Michael Mann"), finished = true),
            film("Collateral", 2004, genres = listOf("Crime", "Thriller"), directors = listOf("Michael Mann"), finished = true),
            film("Se7en", 1995, genres = listOf("Crime", "Mystery"), directors = listOf("David Fincher"), finished = true),
            film("Toy Story", 1995, genres = listOf("Animation"), directors = listOf("John Lasseter"), collection = "Toy Story Collection", finished = true),
            film("Toy Story 2", 1999, genres = listOf("Animation"), directors = listOf("John Lasseter"), collection = "Toy Story Collection", finished = true),
            film("Dr No", 1962, franchise = "007", collection = "James Bond Collection", finished = true),
            film("Goldfinger", 1964, franchise = "007", collection = "James Bond Collection", finished = true),
            film("Up", 2009, genres = listOf("Animation"), finished = true),
            film("Ratatouille", 2007, genres = listOf("Animation"), finished = true),
        )
        val shelves = FilmShelves.build(films, now)
        val titles = shelves.map { it.title }
        assertTrue("Toy Story Collection" in titles)
        assertFalse("James Bond Collection" in titles)          // 007 is already a folder row
        assertEquals(listOf("Collateral", "Se7en", "Heat"), shelves.first { it.kind == ShelfKind.Genre("Crime") }.itemKeys)
        assertTrue("Animation" in titles)
        assertFalse("Drama" in titles)                          // only one film
        assertEquals(listOf("Heat", "Se7en", "Toy Story", "Toy Story 2"), shelves.first { it.kind == ShelfKind.Decade(1990) }.itemKeys)
        assertTrue("Directed by Michael Mann" in titles)
        assertFalse("Directed by David Fincher" in titles)
    }

    @Test fun homeVideoShelvesFindTodaysMemoriesAndYears() {
        val clips = listOf(
            ShelfInput("a", "", now.minus(Duration.ofDays(365 * 3L)), now.minus(Duration.ofDays(400)), 0.0, 30.0, isFinished = false),
            ShelfInput("b", "Trip", now.minus(Duration.ofDays(40)), now.minus(Duration.ofDays(40)), 0.0, 30.0, isFinished = false),
            ShelfInput("c", "Trip", null, now, 0.0, 30.0, isFinished = false),
        )
        val shelves = ShelfBuilder.build(clips, now, ZoneOffset.UTC)
        assertEquals(listOf("a"), shelves.first { it.kind == ShelfKind.OnThisDay }.itemKeys)
        assertEquals(listOf("c"), shelves.first { it.kind == ShelfKind.Undated }.itemKeys)
        assertEquals(listOf("b", "c"), shelves.first { it.kind == ShelfKind.Collection("Trip") }.itemKeys)
    }

    @Test fun matcherAndWatchHistoryAgreeWithTheAppleApp() {
        assertEquals("oceans eleven", TitleMatcher.normalize("Ocean’s Eleven"))
        assertEquals("amelie", TitleMatcher.normalize("Amélie"))
        assertEquals("fast and the furious", TitleMatcher.normalize("The Fast & the Furious"))
        val dunes = listOf(
            TitleMatcher.Candidate(1, listOf("Dune: Part Two"), 2024, 900.0),
            TitleMatcher.Candidate(2, listOf("Dune"), 1984, 40.0),
            TitleMatcher.Candidate(3, listOf("Dune"), 2021, 300.0),
        )
        assertEquals(2, TitleMatcher.best(dunes, "Dune", 1984))
        assertEquals(3, TitleMatcher.best(dunes, "Dune", null))
        assertNull(TitleMatcher.best(listOf(TitleMatcher.Candidate(7, listOf("Star Wars"), 1977, 1.0)), "Star Wars Episode IV", 1997))

        val records = listOf(WatchHistory.Candidate(5_000_000, 1), WatchHistory.Candidate(9_000_000, 2), WatchHistory.Candidate(10, 3))
        assertEquals(0, WatchHistory.bestMatch(5_000_000, records))     // same size wins
        assertEquals(2, WatchHistory.bestMatch(7_000_000, records))     // only the unknown size is possible
    }
}
