package com.khush.movienight.ui

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlin.math.roundToLong

object Formatters {
    /** "2h 14m", "48m", "35s". */
    fun duration(seconds: Double?): String? {
        val total = seconds?.roundToLong()?.takeIf { it > 0 } ?: return null
        val hours = total / 3600
        val minutes = (total % 3600) / 60
        return when {
            hours > 0 -> "${hours}h ${minutes}m"
            minutes > 0 -> "${minutes}m"
            else -> "${total}s"
        }
    }

    /** "1:02:03" or "4:05", stamped on artwork. */
    fun clock(seconds: Double?): String? {
        val total = seconds?.roundToLong()?.takeIf { it > 0 } ?: return null
        val h = total / 3600
        val m = (total % 3600) / 60
        val s = total % 60
        return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%d:%02d".format(m, s)
    }

    fun remaining(seconds: Double?): String? = duration(seconds)?.let { "$it left" }

    fun date(instant: Instant?): String? =
        instant?.let { DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withZone(ZoneId.systemDefault()).format(it) }

    fun size(bytes: Long): String {
        val units = listOf("bytes", "KB", "MB", "GB", "TB")
        var value = bytes.toDouble()
        var unit = 0
        while (value >= 1000 && unit < units.lastIndex) { value /= 1000; unit++ }
        return if (unit == 0) "$bytes bytes" else "%.1f %s".format(value, units[unit])
    }

    fun resolution(width: Int?, height: Int?): String? {
        if (width == null || height == null) return null
        val short = minOf(width, height)
        val long = maxOf(width, height)
        val name = when {
            long >= 3200 || short >= 2000 -> "4K"
            short >= 1000 -> "1080p"
            short >= 700 -> "720p"
            else -> "SD"
        }
        return "$width × $height ($name)"
    }

    fun badge(width: Int?, height: Int?): String? {
        if (width == null || height == null) return null
        val short = minOf(width, height)
        val long = maxOf(width, height)
        return when {
            long >= 3200 || short >= 2000 -> "4K"
            short >= 700 -> "HD"
            else -> null
        }
    }
}
