package com.khush.movienight.core

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/** Dialogue, loudness and balance. The same settings, and the same sound, as the Apple app. */
data class SoundSettings(
    val dialogueBoost: Boolean = false,
    /** Evens out loud and quiet scenes, for watching late or with others asleep. */
    val nightMode: Boolean = false,
    /** -1 is all left, 1 is all right. */
    val balance: Double = 0.0,
) {
    val isNeutral: Boolean get() = !dialogueBoost && !nightMode && abs(balance) < 0.01

    companion object {
        /** Left and right gains for a balance: the far side fades out, the near side stays at full level. */
        fun balanceGains(balance: Double): Pair<Float, Float> {
            val b = balance.coerceIn(-1.0, 1.0).toFloat()
            return minOf(1f, 1 - b) to minOf(1f, 1 + b)
        }
    }
}

/** RBJ cookbook biquad, transposed direct form II. */
class Biquad(
    private val b0: Float = 1f, private val b1: Float = 0f, private val b2: Float = 0f,
    private val a1: Float = 0f, private val a2: Float = 0f,
) {
    private var z1 = 0f
    private var z2 = 0f

    fun process(x: Float): Float {
        val y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }

    /** Magnitude response in dB at a frequency, for tests. */
    fun responseDB(frequency: Double, sampleRate: Double): Double {
        val w = 2 * PI * frequency / sampleRate
        fun mag(c0: Float, c1: Float, c2: Float): Double {
            val re = c0 + c1 * cos(-w) + c2 * cos(-2 * w)
            val im = c1 * sin(-w) + c2 * sin(-2 * w)
            return sqrt(re * re + im * im)
        }
        return 20 * log10(mag(b0, b1, b2) / mag(1f, a1, a2))
    }

    companion object {
        fun peaking(frequency: Double, q: Double, gainDB: Double, sampleRate: Double): Biquad {
            val a = 10.0.pow(gainDB / 40)
            val w0 = 2 * PI * frequency / sampleRate
            val alpha = sin(w0) / (2 * q)
            val a0 = 1 + alpha / a
            return Biquad(
                b0 = ((1 + alpha * a) / a0).toFloat(), b1 = (-2 * cos(w0) / a0).toFloat(), b2 = ((1 - alpha * a) / a0).toFloat(),
                a1 = (-2 * cos(w0) / a0).toFloat(), a2 = ((1 - alpha / a) / a0).toFloat(),
            )
        }
    }
}

/** Feed-forward peak compressor with makeup gain: loud scenes come down, quiet ones come up. */
class Compressor(sampleRate: Double, private val thresholdDB: Float = -26f, private val ratio: Float = 4f, private val makeupDB: Float = 8f) {
    private val attack = exp(-1 / (0.005 * sampleRate)).toFloat()
    private val release = exp(-1 / (0.250 * sampleRate)).toFloat()
    private var envelope = 0f

    /** Linear gain to apply for a sample whose peak across channels is [level]. */
    fun gain(level: Float): Float {
        val coefficient = if (level > envelope) attack else release
        envelope = coefficient * envelope + (1 - coefficient) * level
        val levelDB = 20 * log10(max(envelope, 1e-6f))
        val over = levelDB - thresholdDB
        val reductionDB = if (over > 0) over - over / ratio else 0f
        return 10f.pow((makeupDB - reductionDB) / 20)
    }
}

/**
 * Applies [SoundSettings] to interleaved float samples in place, exactly as the Apple app does:
 * a speech-presence lift (with headroom so it doesn't clip), the night-mode compressor, then balance.
 * Settings can change between calls; the filters follow.
 */
class SoundEffects(private val sampleRate: Double, private val channels: Int) {
    private var equalizers: List<Biquad> = emptyList()
    private var appliedDialogue: Boolean? = null
    private val compressor = Compressor(sampleRate)

    fun process(samples: FloatArray, frames: Int, settings: SoundSettings) {
        if (settings.isNeutral || frames <= 0 || channels <= 0) return
        if (appliedDialogue != settings.dialogueBoost) {
            val gain = if (settings.dialogueBoost) 6.0 else 3.0
            equalizers = List(channels) { Biquad.peaking(2500.0, 0.9, gain, sampleRate) }
            appliedDialogue = settings.dialogueBoost
        }
        val useEQ = settings.dialogueBoost || settings.nightMode
        val headroom = if (settings.dialogueBoost) 0.63f else if (settings.nightMode) 0.8f else 1f
        val (leftGain, rightGain) = SoundSettings.balanceGains(settings.balance)
        for (frame in 0 until frames) {
            val base = frame * channels
            var peak = 0f
            for (c in 0 until channels) {
                var x = samples[base + c] * headroom
                if (useEQ) x = equalizers[c].process(x)
                samples[base + c] = x
                peak = max(peak, abs(x))
            }
            val dynamics = if (settings.nightMode) compressor.gain(peak) else 1f
            for (c in 0 until channels) {
                var x = samples[base + c] * dynamics
                if (channels >= 2 && c == 0) x *= leftGain
                if (channels >= 2 && c == 1) x *= rightGain
                samples[base + c] = x.coerceIn(-1f, 1f)
            }
        }
    }
}
