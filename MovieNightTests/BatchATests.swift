import AVFoundation
import Foundation
import Libmpv
import Testing
@testable import MovieNight

struct PresetTests {
    @Test func settingsMapBackToTheirPreset() {
        for preset in PlaybackPreset.allCases {
            #expect(PlaybackPreset.matching(videoQuality: preset.videoQuality, dialogueBoost: preset.sound.dialogueBoost,
                                            nightMode: preset.sound.nightMode) == preset)
        }
        // Night mode alone is nobody's preset.
        #expect(PlaybackPreset.matching(videoQuality: .standard, dialogueBoost: false, nightMode: true) == nil)
    }

    @Test func mpvFilterChain() {
        #expect(SoundSettings().mpvAudioFilter == "")
        let dialogue = SoundSettings(dialogueBoost: true).mpvAudioFilter
        #expect(dialogue.hasPrefix("lavfi=["))
        #expect(dialogue.contains("equalizer=f=2500"))
        let balanced = SoundSettings(balance: 0.5).mpvAudioFilter
        #expect(balanced.contains("pan=stereo|c0=0.500*c0|c1=1.000*c1"))
        #expect(SoundSettings(nightMode: true).mpvAudioFilter.contains("equalizer=f=70"))
    }

    @Test func balanceKeepsTheNearSideAtFullLevel() {
        #expect(SoundSettings.balanceGains(0) == (1, 1))
        #expect(SoundSettings.balanceGains(-1) == (1, 0))
        #expect(SoundSettings.balanceGains(0.25) == (0.75, 1))
    }
}

struct SoundProcessorTests {
    @Test func dialogueEQBoostsSpeechNotBass() {
        let eq = Biquad.peaking(frequency: 2500, q: 0.9, gainDB: 6, sampleRate: 48_000)
        #expect(abs(eq.responseDB(at: 2500, sampleRate: 48_000) - 6) < 0.1)
        #expect(abs(eq.responseDB(at: 80, sampleRate: 48_000)) < 0.3)
    }

    @Test func compressorTurnsLoudDownAndQuietUp() {
        var loud = Compressor(sampleRate: 48_000), quiet = Compressor(sampleRate: 48_000)
        var loudGain: Float = 1, quietGain: Float = 1
        for _ in 0..<48_000 {
            loudGain = loud.gain(for: 0.9)
            quietGain = quiet.gain(for: 0.01)
        }
        #expect(0.9 * loudGain < 0.9)        // loud scene comes down
        #expect(0.01 * quietGain > 0.01)     // whisper comes up
        #expect(quietGain > loudGain)
    }

    @Test func processesDeinterleavedFloatInPlace() {
        let processor = SoundProcessor(settings: SoundSettings(balance: 1))
        let format = AudioStreamBasicDescription(
            mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 2,
            mBitsPerChannel: 32, mReserved: 0)
        processor.prepare(format: format)
        let frames = 64
        let left = UnsafeMutablePointer<Float>.allocate(capacity: frames), right = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        defer { left.deallocate(); right.deallocate() }
        left.initialize(repeating: 0.5, count: frames)
        right.initialize(repeating: 0.5, count: frames)
        let list = AudioBufferList.allocate(maximumBuffers: 2)
        defer { free(list.unsafeMutablePointer) }
        list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: left)
        list[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: right)

        processor.process(list, frames: frames)
        #expect(left[frames - 1] == 0)        // balance fully right silences the left
        #expect(right[frames - 1] == 0.5)

        processor.update(SoundSettings())
        left.update(repeating: 0.5, count: frames)
        processor.process(list, frames: frames)
        #expect(left[0] == 0.5)               // neutral settings leave audio untouched
    }
}

struct LibraryHealthTests {
    private let mb: Int64 = 1_000_000

    @Test func findsCopiesUnplayableAndNotDownloaded() {
        let items = [
            HealthInput(key: "a/Wedding.mov", fileName: "Wedding.mov", fileSize: 900 * mb, duration: 3600, isPlayable: true, isLocal: true),
            HealthInput(key: "b/Wedding copy.mov", fileName: "Wedding copy.mov", fileSize: 900 * mb, duration: 3600.2, isPlayable: true, isLocal: true),
            HealthInput(key: "c/other.mov", fileName: "other.mov", fileSize: 900 * mb, duration: 120, isPlayable: true, isLocal: true),
            HealthInput(key: "d/broken.avi", fileName: "broken.avi", fileSize: 5 * mb, duration: nil, isPlayable: false, isLocal: true),
            HealthInput(key: "e/IMG_1.MOV", fileName: "IMG_1.MOV", fileSize: 200, duration: nil, isPlayable: nil, isLocal: false),
            HealthInput(key: "f/IMG_1.MOV", fileName: "IMG_1.MOV", fileSize: 200, duration: nil, isPlayable: nil, isLocal: false),
        ]
        let health = LibraryHealth.check(items)
        #expect(health.duplicates == [["a/Wedding.mov", "b/Wedding copy.mov"]])  // placeholders never count
        #expect(health.unplayable == ["d/broken.avi"])
        #expect(health.notDownloaded == ["e/IMG_1.MOV", "f/IMG_1.MOV"])
        #expect(health.count == 4)
    }
}

struct ChapterTests {
    @Test func chaptersRoundTripThroughTheModel() {
        let item = MediaItem(key: "k", relativePath: "a.mkv", collection: "", fileName: "a.mkv", fileSize: 1, fileCreatedAt: nil)
        #expect(item.chapters.isEmpty)
        item.chapters = [Chapter(title: "Ceremony", start: 0), Chapter(title: "Speeches", start: 1830.5)]
        #expect(item.chapters.map(\.title) == ["Ceremony", "Speeches"])
        item.chapters = []
        #expect(item.chaptersData == nil)
    }
}

/// Real audio through both engines' effect paths, using a generated stereo tone.
struct SoundPipelineTests {
    /// 1 s of 440 Hz at half scale on both channels, 16-bit PCM WAV.
    static func makeTone() throws -> URL {
        let rate = 48_000, frames = rate
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + frames * 4))
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(2))
        append(UInt32(rate)); append(UInt32(rate * 4)); append(UInt16(4)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(UInt32(frames * 4))
        for i in 0..<frames {
            let sample = Int16(16_000 * sin(2 * Double.pi * 440 * Double(i) / Double(rate)))
            append(sample); append(sample)
        }
        let url = URL.temporaryDirectory.appending(path: "tone-\(UUID().uuidString).wav")
        try data.write(to: url)
        return url
    }

    /// The AVKit path: the tap runs inside an asset reader exactly as it does in AVPlayer.
    @Test func appleTapAppliesBalance() async throws {
        let url = try Self.makeTone()
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)
        let processor = SoundProcessor(settings: SoundSettings(balance: 1))
        let mix = try #require(await processor.audioMix(for: asset))

        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false, AVNumberOfChannelsKey: 2,
        ])
        output.audioMix = mix
        reader.add(output)
        #expect(reader.startReading())

        var leftPeak: Float = 0, rightPeak: Float = 0
        while let buffer = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
            let length = CMBlockBufferGetDataLength(block)
            var bytes = [Float](repeating: 0, count: length / 4)
            _ = bytes.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
            for frame in stride(from: 0, to: bytes.count - 1, by: 2) {
                leftPeak = max(leftPeak, abs(bytes[frame])); rightPeak = max(rightPeak, abs(bytes[frame + 1]))
            }
        }
        #expect(rightPeak > 0.4)
        #expect(leftPeak < 0.001)
    }

    /// The mpv path: every chain must load in MPVKit's FFmpeg, or mpv drops it and plays unprocessed.
    @Test(.serialized, arguments: [
        SoundSettings(dialogueBoost: true), SoundSettings(nightMode: true),
        SoundSettings(balance: -0.4), SoundSettings(dialogueBoost: true, nightMode: true, balance: 0.3),
    ])
    func mpvAcceptsFilterChain(_ settings: SoundSettings) throws {
        let url = try Self.makeTone()
        defer { try? FileManager.default.removeItem(at: url) }
        let mpv = try #require(MPVHandle())
        defer { mpv.destroy() }
        for (name, value) in [("config", "no"), ("terminal", "no"), ("ao", "null"), ("vo", "null"), ("af", settings.mpvAudioFilter)] {
            mpv.setOption(name, value)
        }
        #expect(mpv.initialize())
        mpv_request_log_messages(mpv.raw, "warn")
        mpv.command(["loadfile", url.path])

        var problems: [String] = [], started = false
        let deadline = Date.now.addingTimeInterval(10)
        loop: while Date.now < deadline {
            guard let event = mpv_wait_event(mpv.raw, 1) else { continue }
            switch event.pointee.event_id {
            case MPV_EVENT_LOG_MESSAGE:
                // Only the audio chain's own complaints; teardown chatter from the core isn't relevant.
                if let message = event.pointee.data?.assumingMemoryBound(to: mpv_event_log_message.self).pointee,
                   String(cString: message.prefix) != "cplayer" {
                    problems.append(String(cString: message.prefix) + ": " + String(cString: message.text))
                }
            case MPV_EVENT_PLAYBACK_RESTART:
                started = true
                break loop
            case MPV_EVENT_END_FILE, MPV_EVENT_SHUTDOWN:
                break loop
            default:
                continue
            }
        }
        #expect(started)
        #expect(problems.isEmpty, "\(problems)")
    }
}
