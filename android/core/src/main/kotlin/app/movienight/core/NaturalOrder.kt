package app.movienight.core

import java.text.Collator
import java.util.Locale

/**
 * Finder-style ordering, the Kotlin side of Swift's `localizedStandardCompare`: case and accents
 * ignored, and numbers compared by value, so "Rocky 2" comes before "Rocky 10".
 */
object NaturalOrder : Comparator<String> {
    private val chunk = Regex("""\d+|\D+""")
    private val collator: Collator = Collator.getInstance(Locale.ROOT).apply { strength = Collator.PRIMARY }

    override fun compare(a: String, b: String): Int {
        val left = chunk.findAll(a).map { it.value }.toList()
        val right = chunk.findAll(b).map { it.value }.toList()
        for (index in 0 until minOf(left.size, right.size)) {
            val x = left[index]
            val y = right[index]
            val result = if (x[0].isDigit() && y[0].isDigit()) {
                x.trimStart('0').length.compareTo(y.trimStart('0').length).takeIf { it != 0 }
                    ?: x.trimStart('0').compareTo(y.trimStart('0'))
            } else {
                synchronized(collator) { collator.compare(x, y) }
            }
            if (result != 0) return result
        }
        return left.size.compareTo(right.size)
    }
}
