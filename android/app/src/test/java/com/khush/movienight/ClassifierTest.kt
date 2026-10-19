package com.khush.movienight

import com.khush.movienight.core.Classification
import com.khush.movienight.core.ClassifierInput
import com.khush.movienight.core.ContentClassifier
import com.khush.movienight.core.ContentClassifier.CleanTitle
import com.khush.movienight.core.ContentKind
import com.khush.movienight.core.DisplayTitle
import com.khush.movienight.core.FolderContent
import com.khush.movienight.core.NaturalOrder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.util.Locale

/** The same cases as the Apple app's OrganisationTests, so both apps sort a library the same way. */
class ClassifierTest {
    private fun classify(paths: List<String>, folder: FolderContent = FolderContent.FILMS_AND_TV, duration: Double? = 3600.0) =
        ContentClassifier.classify(paths.map { ClassifierInput(it, it, it.substringAfterLast('/'), duration) }, folder, currentYear = 2026)

    @Test fun cleansFilmTitlesAndReadsYearsOnlyWhenTheyAreYears() {
        assertEquals(CleanTitle("Interstellar", null), ContentClassifier.cleanTitle("Interstellar "))
        assertEquals(CleanTitle("Dr No", 1962), ContentClassifier.cleanTitle("Dr No (1962)"))
        assertEquals(CleanTitle("Blade Runner 2049", null), ContentClassifier.cleanTitle("Blade Runner 2049"))   // part of the title
        assertEquals(CleanTitle("Heat", 1995), ContentClassifier.cleanTitle("Heat.1995.1080p.BluRay.x264"))
        assertEquals(CleanTitle("The Matrix", 1999), ContentClassifier.cleanTitle("The Matrix (1999) [YTS] (1080p BluRay x265)"))
        assertEquals(CleanTitle("Top Gun Maverick", null), ContentClassifier.cleanTitle("Top Gun Maverick "))
    }

    @Test fun readsEveryEpisodeNamingStyle() {
        assertEquals(ContentClassifier.Episode("Succession", 1, 10, null, null), ContentClassifier.parseEpisode("Succession S1E10"))
        assertEquals(1, ContentClassifier.parseEpisode("The White Lotus S01E01")?.episode)
        assertEquals(
            ContentClassifier.Episode("Invincible", 1, 3, "Who Are You Calling Ugly", 2021),
            ContentClassifier.parseEpisode("Invincible (2021) - S01E03 - Who Are You Calling Ugly (1080p WEB-DL x265 SAMPA)"),
        )
        assertEquals(2, ContentClassifier.parseEpisode("the.wire.s02e05.720p")?.season)
        assertEquals(3, ContentClassifier.parseEpisode("Fargo 2x03")?.episode)
        assertNull(ContentClassifier.parseEpisode("Ocean's Eleven"))
        assertEquals(3, ContentClassifier.seasonNumber("The White Lotus Season 3"))
    }

    @Test fun sortsAFilmsFolderIntoFilmsFranchisesShowsAndExtras() {
        val results = classify(listOf(
            "Inception.mkv", "Blade Runner 2049.mkv", "007/Dr No (1962).mp4", "Dune/Dune 2.mp4",
            "Succession/Succession Season 2/Succession S2E1.mkv",
            "Invincible (2021)/Invincible (2021) - S01E01 - It's About Time (1080p WEB-DL x265 SAMPA).mkv",
            "The Wire/Season 1/The Wire S1E1.mkv", "The Wire/Featurettes/Season 4/The Game Is Real.mkv",
        ))
        assertEquals(ContentKind.FILM, results["Inception.mkv"]?.kind)
        assertNull(results["Inception.mkv"]?.franchise)
        assertEquals("Blade Runner 2049", results["Blade Runner 2049.mkv"]?.title)
        assertEquals(Classification(ContentKind.FILM, "Dr No", year = 1962, franchise = "007"), results["007/Dr No (1962).mp4"])
        assertEquals("Dune", results["Dune/Dune 2.mp4"]?.franchise)
        val succession = results.getValue("Succession/Succession Season 2/Succession S2E1.mkv")
        assertTrue(succession.kind == ContentKind.EPISODE && succession.show == "Succession" && succession.season == 2)
        val invincible = results.getValue("Invincible (2021)/Invincible (2021) - S01E01 - It's About Time (1080p WEB-DL x265 SAMPA).mkv")
        assertTrue(invincible.show == "Invincible" && invincible.episodeTitle == "It's About Time" && invincible.year == 2021)
        val extra = results.getValue("The Wire/Featurettes/Season 4/The Game Is Real.mkv")
        assertTrue(extra.kind == ContentKind.EXTRA && extra.show == "The Wire")
    }

    @Test fun folderChoiceDecides() {
        val paths = listOf("IMG_1234.MOV", "Birthday.mp4", "Holiday S1E1.mp4")
        assertTrue(classify(paths, FolderContent.HOME_VIDEOS).values.all { it.kind == ContentKind.HOME_VIDEO })
        val guessed = classify(paths, FolderContent.AUTO, duration = 120.0)
        assertEquals(ContentKind.HOME_VIDEO, guessed["IMG_1234.MOV"]?.kind)
        assertEquals(ContentKind.HOME_VIDEO, guessed["Birthday.mp4"]?.kind)        // short, so a clip
        assertEquals(ContentKind.EPISODE, guessed["Holiday S1E1.mp4"]?.kind)
        assertEquals(ContentKind.FILM, classify(paths, FolderContent.FILMS_AND_TV, duration = 120.0)["Birthday.mp4"]?.kind)
    }

    @Test fun cameraNamesBecomeDatesAndOtherNamesAreTidied() {
        assertTrue(DisplayTitle.isCameraName("IMG_4821"))
        assertTrue(DisplayTitle.isCameraName("PXL_20230712_181502"))
        assertTrue(DisplayTitle.isCameraName("20190714_153012"))
        assertFalse(DisplayTitle.isCameraName("Wedding Speech"))
        assertEquals("summer holiday 2019 final", DisplayTitle.clean("summer_holiday-2019.final"))
        val date = Instant.parse("2023-07-12T12:00:00Z")
        assertEquals("Wed 12 July 2023", DisplayTitle.make("IMG_1.MOV", date, java.time.ZoneOffset.UTC, Locale.UK))
        assertEquals("Beach Day", DisplayTitle.make("Beach_Day.mp4", date))
    }

    @Test fun naturalOrderComparesNumbersByValue() {
        assertEquals(listOf("Episode 2", "Episode 10", "rocky", "Rocky II"), listOf("Rocky II", "Episode 10", "rocky", "Episode 2").sortedWith(NaturalOrder))
    }
}

class DevicePathsTest {
    @Test fun eachTopFolderIsTreatedLikeAPickedFolder() {
        val arranged = com.khush.movienight.library.DevicePaths.arrange(listOf(
            "/storage/emulated/0/Movies/Films/007/Skyfall.mp4",
            "/storage/emulated/0/Movies/Films/Succession/Season 1/Succession S1E1.mkv",
            "/storage/emulated/0/Movies/Films/Inception.mkv",
            "/storage/emulated/0/DCIM/Camera/IMG_1.mp4",
            "/storage/emulated/0/DCIM/Camera/IMG_2.mp4",
            "/storage/1A2B-3C4D/Shows/The Wire/The Wire S1E1.mkv",
        )).map { it.relative }
        assertEquals(listOf("007/Skyfall.mp4", "Succession/Season 1/Succession S1E1.mkv", "Inception.mkv", "IMG_1.mp4", "IMG_2.mp4",
                            "The Wire S1E1.mkv"), arranged)
    }
}
