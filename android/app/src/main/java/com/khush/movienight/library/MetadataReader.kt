package com.khush.movienight.library

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import java.io.File
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

data class VideoMetadata(
    val duration: Double?,
    val width: Int?,
    val height: Int?,
    val frameRate: Double?,
    val recordedAt: Long?,
    val isPlayable: Boolean?,
    val thumbnailFile: String?,
)

/** Length, size, shooting date and a frame for artwork, read with the system's own media reader. */
object MetadataReader {
    /** Bump to re-read every file on the next scan. */
    const val VERSION = 1

    fun thumbnailDirectory(context: Context): File = File(context.cacheDir, "thumbnails").apply { mkdirs() }

    fun thumbnailName(key: String): String =
        MessageDigest.getInstance("SHA-256").digest(key.toByteArray()).joinToString("") { "%02x".format(it) } + ".jpg"

    fun read(context: Context, uri: Uri, key: String, makeThumbnail: Boolean): VideoMetadata {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(context, uri)
            val hasVideo = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO) == "yes"
            val durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
            var width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull()
            var height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull()
            val rotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            // Phones store portrait video as landscape plus a rotation.
            if (rotation == 90 || rotation == 270) width = height.also { height = width }
            val frameRate = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_CAPTURE_FRAMERATE)?.toDoubleOrNull()
            val recordedAt = parseDate(retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DATE))
            val thumbnail = if (makeThumbnail && hasVideo) frame(context, retriever, key, durationMs) else null
            VideoMetadata(durationMs?.div(1000.0), width, height, frameRate, recordedAt, if (hasVideo) true else null, thumbnail)
        } catch (_: Exception) {
            // Formats the system reader doesn't know (some MKV, AVI, WMV) may still play in ExoPlayer.
            VideoMetadata(null, null, null, null, null, null, null)
        } finally {
            runCatching { retriever.release() }
        }
    }

    /** A frame 10% in: the first frame of home video is often black or a blur of a pocket. */
    private fun frame(context: Context, retriever: MediaMetadataRetriever, key: String, durationMs: Long?): String? {
        val timeUs = (durationMs ?: 0) * 100
        val bitmap = runCatching {
            if (Build.VERSION.SDK_INT >= 27) {
                retriever.getScaledFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, 1280, 720)
            } else {
                retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)?.let { scaled(it) }
            }
        }.getOrNull() ?: return null
        val name = thumbnailName(key)
        return runCatching {
            File(thumbnailDirectory(context), name).outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 80, it) }
            name
        }.getOrNull().also { bitmap.recycle() }
    }

    private fun scaled(bitmap: Bitmap): Bitmap {
        val scale = minOf(1280f / bitmap.width, 720f / bitmap.height, 1f)
        if (scale >= 1f) return bitmap
        return Bitmap.createScaledBitmap(bitmap, (bitmap.width * scale).toInt(), (bitmap.height * scale).toInt(), true).also { bitmap.recycle() }
    }

    /** "20230712T181502.000Z", the MP4 creation date. Encoders write 1904 or 1970 when they don't know. */
    private fun parseDate(raw: String?): Long? {
        if (raw.isNullOrBlank()) return null
        for (pattern in listOf("yyyyMMdd'T'HHmmss.SSS'Z'", "yyyyMMdd'T'HHmmss'Z'", "yyyy MM dd")) {
            val format = SimpleDateFormat(pattern, Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC"); isLenient = false }
            val date = runCatching { format.parse(raw) }.getOrNull() ?: continue
            return date.time.takeIf { it > 315_532_800_000L }   // after 1980
        }
        return null
    }
}
