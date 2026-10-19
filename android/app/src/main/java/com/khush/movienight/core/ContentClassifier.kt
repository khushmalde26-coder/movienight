package com.khush.movienight.core

/** What a video is, which decides where it lives in the app. */
enum class ContentKind { FILM, EPISODE, HOME_VIDEO, EXTRA }

/** What the user says a folder holds, chosen when it's added. AUTO guesses per file. */
enum class FolderContent(val title: String, val summary: String) {
    FILMS_AND_TV("Films & TV", "Loose files are films, folders of films are franchises, folders with S1E2-style names are TV shows."),
    HOME_VIDEOS("Home Videos", "Everything is a home video, arranged by when it was recorded."),
    AUTO("Let Movie Night Decide", "Camera clips become home videos, files named like S1E2 become TV episodes, the rest are films."),
}

data class ClassifierInput(
    val key: String,
    /** Relative to the library folder, e.g. "Succession/Succession Season 1/Succession S1E1.mkv". */
    val relativePath: String,
    val fileName: String,
    val duration: Double?,
)

data class Classification(
    val kind: ContentKind,
    /** Cleaned film title, or the show name for episodes and extras of a show. */
    val title: String,
    val show: String? = null,
    val season: Int? = null,
    val episode: Int? = null,
    val episodeTitle: String? = null,
    val year: Int? = null,
    /** The folder a film sits in alongside related films (007, Dune, Kill Bill). */
    val franchise: String? = null,
)

/** Works out films, TV episodes, extras and home videos from names and folders alone (no network). Same rules as the Apple app. */
object ContentClassifier {
    /** Clips shorter than this, with no episode number, count as home videos when guessing. */
    const val HOME_VIDEO_MAXIMUM = 8 * 60.0
    val extraFolders = setOf(
        "featurettes", "extras", "bonus", "bonus features", "behind the scenes", "deleted scenes",
        "interviews", "trailers", "shorts", "special features",
    )

    fun classify(inputs: List<ClassifierInput>, folder: FolderContent, currentYear: Int = java.time.Year.now().value): Map<String, Classification> {
        // A top-level folder with any episode in it is a TV show; everything else in it is an extra.
        val showFolders = inputs.filter { parseEpisode(DisplayTitle.stem(it.fileName)) != null }
            .mapNotNull { topFolder(it.relativePath) }.toSet()
        return inputs.associate { it.key to classifyOne(it, folder, showFolders, currentYear) }
    }

    private fun classifyOne(input: ClassifierInput, folder: FolderContent, showFolders: Set<String>, currentYear: Int): Classification {
        val name = DisplayTitle.stem(input.fileName)
        val components = input.relativePath.split("/").filter { it.isNotEmpty() }.dropLast(1)
        val top = components.firstOrNull()
        val cleaned = cleanTitle(name, currentYear)

        if (folder == FolderContent.HOME_VIDEOS) {
            return Classification(ContentKind.HOME_VIDEO, DisplayTitle.clean(name))
        }
        if (components.any { it.lowercase() in extraFolders }) {
            return Classification(ContentKind.EXTRA, cleaned.title, show = top?.let { cleanTitle(it, currentYear).title })
        }
        parseEpisode(name, currentYear)?.let { parsed ->
            val folderShow = top?.let { cleanTitle(it, currentYear) }
            val show = folderShow?.title ?: parsed.show ?: cleaned.title
            val season = parsed.season ?: components.firstNotNullOfOrNull { seasonNumber(it) }
            return Classification(
                ContentKind.EPISODE, show, show = show, season = season ?: 1, episode = parsed.episode,
                episodeTitle = parsed.title, year = folderShow?.year ?: parsed.year,
            )
        }
        if (top != null && top in showFolders) {
            return Classification(ContentKind.EXTRA, cleaned.title, show = cleanTitle(top, currentYear).title)
        }
        if (folder == FolderContent.AUTO && (DisplayTitle.isCameraName(name) || (input.duration ?: Double.POSITIVE_INFINITY) < HOME_VIDEO_MAXIMUM)) {
            return Classification(ContentKind.HOME_VIDEO, DisplayTitle.clean(name))
        }
        return Classification(ContentKind.FILM, cleaned.title, year = cleaned.year, franchise = top?.let { cleanTitle(it, currentYear).title })
    }

    // Parsing

    data class Episode(val show: String?, val season: Int?, val episode: Int, val title: String?, val year: Int?)

    private val episodePatterns = listOf(
        Regex("""\bS(\d{1,2})\s*E(\d{1,3})\b""", RegexOption.IGNORE_CASE),
        Regex("""\b(\d{1,2})x(\d{2,3})\b""", RegexOption.IGNORE_CASE),
    )

    /**
     * "Succession S1E10", "The White Lotus S01E01", "Invincible (2021) - S01E01 - It's About Time (1080p…)",
     * "the.wire.s01e02.720p", "Fargo 2x03".
     */
    fun parseEpisode(stem: String, currentYear: Int = java.time.Year.now().value): Episode? {
        val text = stem.replace(Regex("[._]"), " ")
        for (pattern in episodePatterns) {
            val match = pattern.find(text) ?: continue
            val episode = match.groupValues[2].toIntOrNull() ?: continue
            val before = cleanTitle(text.substring(0, match.range.first), currentYear)
            val after = text.substring(match.range.last + 1).trim(' ', '-', '–', '—', ':')
            val title = cleanTitle(after, currentYear).title
            return Episode(
                show = before.title.ifEmpty { null }, season = match.groupValues[1].toIntOrNull(), episode = episode,
                title = title.ifEmpty { null }, year = before.year,
            )
        }
        return null
    }

    private val seasonPattern = Regex("""\b(?:season|series|s)\s*(\d{1,2})\b""", RegexOption.IGNORE_CASE)

    /** "Season 4", "The White Lotus Season 2", "S03" → the season number. */
    fun seasonNumber(component: String): Int? = seasonPattern.find(component)?.groupValues?.get(1)?.toIntOrNull()

    const val RELEASE_TAGS = """(?i)\b(2160p|1080p|720p|480p|4k|uhd|hdr10?\+?|dv|dolby ?vision|web-?dl|web-?rip|webrip|bluray|blu-ray|brrip|bdrip|dvdrip|hdtv|remux|x26[45]|h ?26[45]|hevc|avc|aac|ac3|dts|ddp?5 ?1|atmos|10bit|proper|repack|extended|unrated|imax|yts|rarbg|sampa)\b"""
    private val releaseTags = Regex(RELEASE_TAGS)
    private val bracketedRelease = Regex("""\((?=[^)]*$RELEASE_TAGS)[^)]*\)""")
    private val yearPattern = Regex("""[(\s]((?:19|20)\d{2})(\))?(?=\s|$)""")

    data class CleanTitle(val title: String, val year: Int?)

    /** "Interstellar " → "Interstellar"; "Dr No (1962)" → ("Dr No", 1962); "Heat.1995.1080p.BluRay" → ("Heat", 1995). */
    fun cleanTitle(raw: String, currentYear: Int = java.time.Year.now().value): CleanTitle {
        var text = raw.replace(Regex("[._]"), " ")
        // Bracketed release info: [YTS], (1080p WEB-DL x265 SAMPA).
        text = text.replace(Regex("""\[[^\]]*]"""), " ")
        text = bracketedRelease.replace(text, " ")
        var year: Int? = null
        val match = yearPattern.findAll(text).lastOrNull()
        val found = match?.groupValues?.get(1)?.toIntOrNull()
        if (match != null && found != null && match.range.first > 0 && found <= currentYear + 1) {
            // "(1962)" is always a year. A bare number only counts with release tags after it
            // ("Heat 1995 1080p"); otherwise it's part of the title ("Blade Runner 2049").
            val bracketed = match.groups[2] != null
            val rest = text.substring(match.range.last + 1)
            if (bracketed || releaseTags.containsMatchIn(rest)) {
                year = found
                // Everything from the year on is release noise.
                text = text.substring(0, match.range.first)
            }
        }
        releaseTags.find(text)?.let { text = text.substring(0, it.range.first) }
        val title = text.split(" ").filter { it.isNotEmpty() }.joinToString(" ").trim(' ', '-', '–', '—', ':', '(')
        return CleanTitle(title.ifEmpty { raw.trim() }, year)
    }

    private fun topFolder(relativePath: String): String? {
        val parts = relativePath.split("/").filter { it.isNotEmpty() }
        return if (parts.size > 1) parts[0] else null
    }
}
