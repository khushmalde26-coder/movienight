package com.khush.movienight

import com.khush.movienight.core.Biquad
import com.khush.movienight.core.SoundEffects
import com.khush.movienight.core.SoundSettings
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin

class SoundTest {
    private val rate = 48_000.0

    /** Interleaved stereo sine, both channels the same. */
    private fun sine(frequency: Double, amplitude: Float, seconds: Double = 0.5): FloatArray {
        val frames = (rate * seconds).toInt()
        return FloatArray(frames * 2) { i -> amplitude * sin(2 * PI * frequency * (i / 2) / rate).toFloat() }
    }

    /** Peak of one channel over the second half, after the filters have settled. */
    private fun peak(samples: FloatArray, channel: Int): Float =
        (samples.size / 4 until samples.size / 2).maxOf { abs(samples[it * 2 + channel]) }

    @Test fun dialogueBoostLiftsSpeechNotBass() {
        val filter = Biquad.peaking(2500.0, 0.9, 6.0, rate)
        assertEquals(6.0, filter.responseDB(2500.0, rate), 0.1)
        assertTrue(filter.responseDB(100.0, rate) < 0.5)

        val speech = sine(2500.0, 0.3f).also { SoundEffects(rate, 2).process(it, it.size / 2, SoundSettings(dialogueBoost = true)) }
        val bass = sine(100.0, 0.3f).also { SoundEffects(rate, 2).process(it, it.size / 2, SoundSettings(dialogueBoost = true)) }
        // Headroom first (×0.63), then +6 dB at 2.5 kHz: speech ends up about where it was, bass quieter.
        assertEquals(0.3f * 0.63f * 2f, peak(speech, 0), 0.03f)
        assertTrue(peak(bass, 0) < 0.3f * 0.7f)
    }

    @Test fun nightModeBringsLoudAndQuietCloser() {
        val loud = sine(1000.0, 0.9f, 1.0).also { SoundEffects(rate, 2).process(it, it.size / 2, SoundSettings(nightMode = true)) }
        val quiet = sine(1000.0, 0.02f, 1.0).also { SoundEffects(rate, 2).process(it, it.size / 2, SoundSettings(nightMode = true)) }
        val before = 0.9f / 0.02f
        val after = peak(loud, 0) / peak(quiet, 0)
        assertTrue("loud/quiet was $before, now $after", after < before / 4)
        assertTrue(peak(loud, 0) <= 1f)
    }

    @Test fun balanceFadesTheFarSideAndNeutralChangesNothing() {
        assertEquals(1f to 0f, SoundSettings.balanceGains(-1.0))
        assertEquals(0.5f to 1f, SoundSettings.balanceGains(0.5))
        val left = sine(440.0, 0.5f).also { SoundEffects(rate, 2).process(it, it.size / 2, SoundSettings(balance = -1.0)) }
        assertEquals(0f, peak(left, 1), 0.0001f)
        assertEquals(0.5f, peak(left, 0), 0.01f)

        val original = sine(440.0, 0.5f)
        val untouched = original.copyOf().also { SoundEffects(rate, 2).process(it, it.size / 2, SoundSettings()) }
        assertArrayEquals(original, untouched, 0f)
    }
}
