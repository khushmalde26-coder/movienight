package com.khush.movienight.library

import android.content.Context
import android.media.MediaFormat
import android.net.Uri
import androidx.media3.common.util.ParsableBitArray
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.extractor.Ac3Util
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.inspector.MediaExtractorCompat
import com.khush.movienight.core.SpatialAudio
import java.nio.ByteBuffer

/**
 * Finds Dolby Atmos in a soundtrack. MP4 declares it in the track; Matroska doesn't, so for Dolby
 * Digital Plus tracks the first frame is read and its Joint Object Coding flag checked.
 */
@UnstableApi
object AudioProbe {
    fun spatialAudio(context: Context, uri: Uri): SpatialAudio? {
        // Media3's extractor, not the system's: the system's drops audio tracks it can't decode itself.
        val extractor = MediaExtractorCompat(DefaultExtractorsFactory(), DefaultDataSource.Factory(context))
        return try {
            extractor.setDataSource(uri, 0)
            (0 until extractor.trackCount).firstNotNullOfOrNull { index ->
                val mime = extractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME) ?: return@firstNotNullOfOrNull null
                SpatialAudio.fromMimeType(mime) ?: if (mime == "audio/eac3") firstFrameIsJoc(extractor, index) else null
            }
        } catch (_: Exception) {
            null
        } finally {
            runCatching { extractor.release() }
        }
    }

    private fun firstFrameIsJoc(extractor: MediaExtractorCompat, track: Int): SpatialAudio? {
        extractor.selectTrack(track)
        val buffer = ByteBuffer.allocate(64 * 1024)
        val size = extractor.readSampleData(buffer, 0)
        extractor.unselectTrack(track)
        if (size < 8) return null
        val bytes = ByteArray(size).also { buffer.position(0); buffer.get(it) }
        return SpatialAudio.fromMimeType(Ac3Util.parseAc3SyncframeInfo(ParsableBitArray(bytes)).mimeType)
    }
}
