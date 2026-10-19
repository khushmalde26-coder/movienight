package app.movienight.core

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Turns file names into something you would put on a poster.
 * Camera names like `IMG_4821.MOV` or `PXL_20230712_181502.mp4` carry no meaning,
 * so those become the recording date. Anything else is tidied up and kept.
 */
object DisplayTitle {
    /** Matched case-insensitively against the file name without its extension. */
    val cameraNamePatterns: List<Regex> = listOf(
        """^(IMG|MVI|DSC[FN]?|DJI|GOPR|G[HX]\d{2}|VID|PXL|MAH|CLIP|MOV|TRIM|RPReplay)[_ -]?\d[\w.-]*$""",
        """^\d{8}[_-]\d{6}\w*$""",            // Android: 20190714_153012
        """^C\d{4}$""",                        // Sony: C0042
        """^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$""", // exported with UUID names
    ).map { Regex(it, RegexOption.IGNORE_CASE) }

    fun isCameraName(stem: String): Boolean = cameraNamePatterns.any { it.containsMatchIn(stem) }

    fun make(fileName: String, recordedAt: Instant?, locale: Locale = Locale.getDefault(), zone: ZoneId = ZoneId.systemDefault()): String {
        val stem = stem(fileName)
        if (isCameraName(stem) && recordedAt != null) {
            return DateTimeFormatter.ofPattern("EEE d MMMM yyyy", locale).format(recordedAt.atZone(zone))
        }
        return clean(stem)
    }

    /** "summer_holiday-2019.final" -> "summer holiday 2019 final" */
    fun clean(stem: String): String {
        val collapsed = stem.replace(Regex("""[_.\-]+"""), " ").split(' ').filter { it.isNotEmpty() }.joinToString(" ")
        return collapsed.ifEmpty { stem }
    }

    /** The file name without its extension. */
    fun stem(fileName: String): String {
        val dot = fileName.lastIndexOf('.')
        return if (dot > 0) fileName.substring(0, dot) else fileName
    }
}
