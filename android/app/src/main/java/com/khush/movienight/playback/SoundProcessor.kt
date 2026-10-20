package com.khush.movienight.playback

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor.AudioFormat
import androidx.media3.common.audio.AudioProcessor.UnhandledAudioFormatException
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import com.khush.movienight.core.SoundEffects
import com.khush.movienight.core.SoundSettings
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Runs [SoundEffects] inside ExoPlayer's audio path, on whatever the decoder produces (16-bit or
 * float PCM). Settings are read on every buffer, so changes during playback are heard at once.
 * Audio sent undecoded to a soundbar or receiver (passthrough) never comes through here.
 */
@UnstableApi
class SoundProcessor(private val settings: () -> SoundSettings) : BaseAudioProcessor() {
    private var effects: SoundEffects? = null
    private var scratch = FloatArray(0)

    override fun onConfigure(inputAudioFormat: AudioFormat): AudioFormat {
        if (inputAudioFormat.encoding != C.ENCODING_PCM_16BIT && inputAudioFormat.encoding != C.ENCODING_PCM_FLOAT) {
            throw UnhandledAudioFormatException(inputAudioFormat)
        }
        effects = SoundEffects(inputAudioFormat.sampleRate.toDouble(), inputAudioFormat.channelCount)
        return inputAudioFormat
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val size = inputBuffer.remaining()
        if (size == 0) return
        val current = settings()
        val output = replaceOutputBuffer(size)
        val format = inputAudioFormat
        if (current.isNeutral || effects == null) {
            output.put(inputBuffer).flip()
            return
        }
        val input = inputBuffer.order(ByteOrder.nativeOrder())
        val float = format.encoding == C.ENCODING_PCM_FLOAT
        val count = if (float) size / 4 else size / 2
        if (scratch.size < count) scratch = FloatArray(count)
        val start = input.position()
        for (i in 0 until count) {
            scratch[i] = if (float) input.getFloat(start + i * 4) else input.getShort(start + i * 2) / 32768f
        }
        input.position(input.limit())
        effects!!.process(scratch, count / format.channelCount, current)
        for (i in 0 until count) {
            if (float) output.putFloat(scratch[i]) else output.putShort((scratch[i] * 32767f).toInt().toShort())
        }
        output.flip()
    }

    override fun onReset() {
        effects = null
    }
}
