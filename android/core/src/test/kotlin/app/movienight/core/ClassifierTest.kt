package app.movienight.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** The same cases as the Apple app's OrganisationTests, built from Khush's real naming styles. */
class ClassifierTest {
    private fun classify(paths: List<String>, folder: FolderContent = FolderContent.FILMS_AND_TV, duration: Double? = 3600.0) =
        ContentClassifier.classify(paths.map { ClassifierInput(it, it, it.substringAfterLast('/'), duration) }, folder)

    @Test fun cleansFilmTitlesAndReadsYearsOnlyWhenTheyAreYears() {
        assertEquals(ContentClassifier.CleanTitle("Interstellar", null), ContentClassifier.cleanTitle("Interstellar "))
        assertEquals(ContentClassifier.CleanTitle("Dr No", 1962), ContentClassifier.cleanTitle("Dr No (1962)"))
        assertEquals(ContentClassifier.CleanTitle("Blade Runner 2049", null), ContentClassifier.cleanTitle("Blade Runner 2049"))
        assertEquals(ContentClassifier.CleanTitle("Heat", 1995), ContentClassifier.cleanTitle("Heat.1995.1080p.BluRay.x264"))
        assertEquals(ContentClassifier.CleanTitle("The Matrix", 1999), ContentClassifier.cleanTitle("The Matrix (1999) [YTS] (1080p BluRay x265)"))
        assertEquals(ContentClassifier.CleanTitle("Top Gun Maverick", null), ContentClassifier.cleanTitle("Top Gun Maverick "))
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
        val invincible = "Invincible (2021)/Invincible (2021) - S01E01 - It's About Time (1080p WEB-DL x265 SAMPA).mkv"
        val results = classify(listOf(
            "Inception.mkv", "Blade Runner 2049.mkv", "007/Dr No (1962).mp4", "Dune/Dune 2.mp4",
            "Succession/Succession Season 2/Succession S2E1.mkv", invincible,
            "The Wire/Season 1/The Wire S1E1.mkv", "The Wire/Featurettes/Season 4/The Game Is Real.mkv",
        ))
        assertEquals(ContentKind.FILM, results["Inception.mkv"]?.kind)
        assertNull(results["Inception.mkv"]?.franchise)
        assertEquals("Blade Runner 2049", results["Blade Runner 2049.mkv"]?.title)
        assertEquals(Classification(ContentKind.FILM, "Dr No", year = 1962, franchise = "007"), results["007/Dr No (1962).mp4"])
        assertEquals("Dune", results["Dune/Dune 2.mp4"]?.franchise)
        val succession = results.getValue("Succession/Succession Season 2/Succession S2E1.mkv")
        assertEquals(Triple(ContentKind.EPISODE, "Succession", 2), Triple(succession.kind, succession.show, succession.season))
        val episode = results.getValue(invincible)
        assertEquals(Triple("Invincible", "It's About Time", 2021), Triple(episode.show, episode.episodeTitle, episode.year))
        val extra = results.getValue("The Wire/Featurettes/Season 4/The Game Is Real.mkv")
        assertEquals(ContentKind.EXTRA to "The Wire", extra.kind to extra.show)
    }

    @Test fun folderChoiceDecides() {
        val paths = listOf("IMG_1234.MOV", "Birthday.mp4", "Holiday S1E1.mp4")
        assertTrue(classify(paths, FolderContent.HOME_VIDEOS).values.all { it.kind == ContentKind.HOME_VIDEO })
        val guessed = classify(paths, FolderContent.AUTO, duration = 120.0)
        assertEquals(ContentKind.HOME_VIDEO, guessed["IMG_1234.MOV"]?.kind)
        assertEquals(ContentKind.HOME_VIDEO, guessed["Birthday.mp4"]?.kind)       // short, so a clip
        assertEquals(ContentKind.EPISODE, guessed["Holiday S1E1.mp4"]?.kind)
        val films = classify(paths, FolderContent.FILMS_AND_TV, duration = 120.0)
        assertEquals(ContentKind.FILM, films["Birthday.mp4"]?.kind)              // the user said films
    }

    @Test fun cameraNamesAndTidyTitles() {
        for (name in listOf("IMG_4821", "PXL_20230712_181502123", "20190714_153012", "GOPR0042", "C0042", "DJI_0007")) {
            assertTrue(DisplayTitle.isCameraName(name), name)
        }
        assertEquals("Grandma's 80th speech", DisplayTitle.make("Grandma's 80th_speech.mov", null))
        assertEquals("The Matrix 1999", DisplayTitle.make("The.Matrix.1999.mkv", null))
        assertEquals("IMG 4821", DisplayTitle.make("IMG_4821.MOV", null))
    }
}
