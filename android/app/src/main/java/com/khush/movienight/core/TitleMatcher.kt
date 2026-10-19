package com.khush.movienight.core

import java.text.Normalizer
import kotlin.math.abs
import kotlin.math.min

/** Which TMDB result is the user's file. Pure, so it's tested. Same rules as the Apple app. */
object TitleMatcher {
    /** One record per film (title and year from the file name) or per show. */
    fun key(kind: ContentKind, title: String?, year: Int?, show: String?): String? = when (kind) {
        ContentKind.FILM -> title?.let { "film|${normalize(it)}|${year ?: 0}" }
        ContentKind.EPISODE, ContentKind.EXTRA -> show?.let { "tv|${normalize(it)}" }
        ContentKind.HOME_VIDEO -> null
    }

    /** "Schindler's List" and "Schindlers List", "Ocean’s Eleven" and "Oceans Eleven", "&" and "and" all compare equal. */
    fun normalize(title: String): String {
        var text = Normalizer.normalize(title, Normalizer.Form.NFD).replace(Regex("""\p{Mn}+"""), "").lowercase()
        text = text.replace("&", " and ")
        text = text.replace(Regex("""['’`]"""), "")
        text = text.replace(Regex("""[^a-z0-9]+"""), " ")
        val words = text.split(" ").filter { it.isNotEmpty() }
        return (if (words.firstOrNull() == "the") words.drop(1) else words).joinToString(" ")
    }

    data class Candidate(val id: Int, val titles: List<String>, val year: Int?, val popularity: Double)

    /**
     * The best candidate, or null when nothing fits. An exact title match wins (a matching year breaks
     * ties); otherwise TMDB's own top result, unless its year contradicts the file's by more than a year.
     */
    fun best(candidates: List<Candidate>, title: String, year: Int?): Int? {
        if (candidates.isEmpty()) return null
        val wanted = normalize(title)
        val exact = candidates.filter { c -> c.titles.any { normalize(it) == wanted } }
        if (exact.isNotEmpty()) return exact.maxBy { score(it, year) }.id
        val top = candidates[0]
        if (year != null && top.year != null && abs(top.year - year) > 1) return null
        return top.id
    }

    private fun score(candidate: Candidate, year: Int?): Double {
        var score = min(candidate.popularity, 1000.0) / 1000
        if (year != null && candidate.year != null) {
            if (candidate.year == year) score += 10 else if (abs(candidate.year - year) == 1) score += 5
        }
        return score
    }
}
