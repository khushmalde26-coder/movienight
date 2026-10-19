import AVFoundation
import MediaToolbox
import os

/// RBJ cookbook biquad, transposed direct form II.
struct Biquad: Sendable {
    var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
    private var z1: Float = 0, z2: Float = 0

    static func peaking(frequency: Double, q: Double, gainDB: Double, sampleRate: Double) -> Biquad {
        let a = pow(10, gainDB / 40)
        let w0 = 2 * Double.pi * frequency / sampleRate
        let alpha = sin(w0) / (2 * q)
        let a0 = 1 + alpha / a
        var filter = Biquad()
        filter.b0 = Float((1 + alpha * a) / a0)
        filter.b1 = Float(-2 * cos(w0) / a0)
        filter.b2 = Float((1 - alpha * a) / a0)
        filter.a1 = Float(-2 * cos(w0) / a0)
        filter.a2 = Float((1 - alpha / a) / a0)
        return filter
    }

    mutating func process(_ x: Float) -> Float {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }

    /// Magnitude response in dB at a frequency, for tests.
    func responseDB(at frequency: Double, sampleRate: Double) -> Double {
        let w = 2 * Double.pi * frequency / sampleRate
        func mag(_ c0: Float, _ c1: Float, _ c2: Float) -> Double {
            let re = Double(c0) + Double(c1) * cos(-w) + Double(c2) * cos(-2 * w)
            let im = Double(c1) * sin(-w) + Double(c2) * sin(-2 * w)
            return (re * re + im * im).squareRoot()
        }
        return 20 * log10(mag(b0, b1, b2) / mag(1, a1, a2))
    }
}

/// Feed-forward peak compressor with makeup gain: loud scenes come down, quiet ones come up.
struct Compressor: Sendable {
    var thresholdDB: Float = -26
    var ratio: Float = 4
    var makeupDB: Float = 8
    private var attack: Float = 0
    private var release: Float = 0
    private var envelope: Float = 0

    init(sampleRate: Double) {
        attack = Float(exp(-1 / (0.005 * sampleRate)))
        release = Float(exp(-1 / (0.250 * sampleRate)))
    }

    /// Linear gain to apply for a sample whose peak across channels is `level`.
    mutating func gain(for level: Float) -> Float {
        let coefficient = level > envelope ? attack : release
        envelope = coefficient * envelope + (1 - coefficient) * level
        let levelDB = 20 * log10(max(envelope, 1e-6))
        let over = levelDB - thresholdDB
        let reductionDB = over > 0 ? over - over / ratio : 0
        return pow(10, (makeupDB - reductionDB) / 20)
    }
}

/// Applies SoundSettings to Apple-player audio through an MTAudioProcessingTap.
/// Settings can change while playing; the render thread reads them under a lock.
final class SoundProcessor: @unchecked Sendable {
    private let settings: OSAllocatedUnfairLock<SoundSettings>
    // Render-thread state, only touched from the tap callbacks.
    private var sampleRate: Double = 48_000
    private var isFloat = false
    private var isInterleaved = false
    private var equalizers: [Biquad] = []
    private var compressor = Compressor(sampleRate: 48_000)
    private var appliedDialogue: Bool?

    init(settings: SoundSettings) {
        self.settings = OSAllocatedUnfairLock(initialState: settings)
    }

    func update(_ new: SoundSettings) {
        settings.withLock { $0 = new }
    }

    func prepare(format: AudioStreamBasicDescription) {
        sampleRate = format.mSampleRate > 0 ? format.mSampleRate : 48_000
        isFloat = format.mFormatFlags & kAudioFormatFlagIsFloat != 0 && format.mBitsPerChannel == 32
        isInterleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        equalizers = Array(repeating: Biquad(), count: Int(max(format.mChannelsPerFrame, 1)))
        compressor = Compressor(sampleRate: sampleRate)
        appliedDialogue = nil
    }

    /// Processes float32 samples in place. Other formats pass through untouched.
    func process(_ buffers: UnsafeMutableAudioBufferListPointer, frames: Int) {
        let current = settings.withLock { $0 }
        guard isFloat, !current.isNeutral, frames > 0 else { return }

        if appliedDialogue != current.dialogueBoost || equalizers.isEmpty {
            let gain = current.dialogueBoost ? 6.0 : 3.0
            let channels = max(equalizers.count, 1)
            equalizers = Array(repeating: .peaking(frequency: 2500, q: 0.9, gainDB: gain, sampleRate: sampleRate), count: channels)
            appliedDialogue = current.dialogueBoost
        }
        let useEQ = current.dialogueBoost || current.nightMode
        let headroom: Float = current.dialogueBoost ? 0.63 : (current.nightMode ? 0.8 : 1)
        let (leftGain, rightGain) = SoundSettings.balanceGains(current.balance)

        // Pointers per channel: deinterleaved has one buffer each, interleaved has one with a stride.
        var channels: [(UnsafeMutablePointer<Float>, Int)] = []
        if isInterleaved, let buffer = buffers.first, let data = buffer.mData {
            let count = Int(buffer.mNumberChannels)
            let base = data.assumingMemoryBound(to: Float.self)
            channels = (0..<count).map { (base + $0, count) }
        } else {
            channels = buffers.compactMap { $0.mData.map { ($0.assumingMemoryBound(to: Float.self), 1) } }
        }
        guard !channels.isEmpty else { return }
        if equalizers.count < channels.count {
            equalizers += Array(repeating: equalizers.first ?? Biquad(), count: channels.count - equalizers.count)
        }

        for frame in 0..<frames {
            var peak: Float = 0
            for (index, (pointer, stride)) in channels.enumerated() {
                var x = pointer[frame * stride] * headroom
                if useEQ { x = equalizers[index].process(x) }
                pointer[frame * stride] = x
                peak = max(peak, abs(x))
            }
            let dynamics = current.nightMode ? compressor.gain(for: peak) : 1
            for (index, (pointer, stride)) in channels.enumerated() {
                var x = pointer[frame * stride] * dynamics
                if channels.count >= 2 && index == 0 { x *= leftGain }
                if channels.count >= 2 && index == 1 { x *= rightGain }
                pointer[frame * stride] = min(max(x, -1), 1)
            }
        }
    }

    // MARK: Tap

    /// An audio mix that runs this processor on the asset's first audio track, or nil if it has none.
    func audioMix(for asset: AVAsset) async -> AVAudioMix? {
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else { return nil }
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passRetained(self).toOpaque(),
            init: { _, clientInfo, storage in storage.pointee = clientInfo },
            finalize: { tap in
                Unmanaged<SoundProcessor>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, _, format in
                Unmanaged<SoundProcessor>.fromOpaque(MTAudioProcessingTapGetStorage(tap))
                    .takeUnretainedValue().prepare(format: format.pointee)
            },
            unprepare: nil,
            process: { tap, frames, _, buffers, framesOut, flagsOut in
                guard MTAudioProcessingTapGetSourceAudio(tap, frames, buffers, flagsOut, nil, framesOut) == noErr else { return }
                Unmanaged<SoundProcessor>.fromOpaque(MTAudioProcessingTapGetStorage(tap))
                    .takeUnretainedValue().process(UnsafeMutableAudioBufferListPointer(buffers), frames: Int(framesOut.pointee))
            }
        )
        var tap: MTAudioProcessingTap?
        guard MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap) == noErr,
              let tap
        else {
            Unmanaged<SoundProcessor>.fromOpaque(callbacks.clientInfo!).release()
            return nil
        }
        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        return mix
    }
}
