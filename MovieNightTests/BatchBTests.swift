import AVFoundation
import Foundation
import Libmpv
import SwiftData
import Testing
@testable import MovieNight

struct SubtitleParserTests {
    @Test func parsesSRTWithTagsAndCRLF() {
        let srt = "1\r\n00:00:01,000 --> 00:00:02,500\r\n<i>Hello</i> there\r\n\r\n2\r\n00:00:03,000 --> 00:00:04,000\r\n{\\an8}Second\r\nline\r\n"
        let cues = SubtitleParser.parse(srt)
        #expect(cues == [
            SubtitleCue(start: 1, end: 2.5, text: "Hello there"),
            SubtitleCue(start: 3, end: 4, text: "Second\nline"),
        ])
    }

    @Test func parsesVTTShortTimesAndSettings() {
        let vtt = "WEBVTT\n\nintro\n00:05.000 --> 00:07.250 align:start\nHi\n\n1:00:00.5 --> 1:00:01.0\nLate"
        let cues = SubtitleParser.parse(vtt)
        #expect(cues.map(\.start) == [5, 3600.5])
        #expect(cues.first?.end == 7.25)
    }

    @Test func findsTheCueOnScreen() {
        let cues = [SubtitleCue(start: 1, end: 2, text: "a"), SubtitleCue(start: 3, end: 5, text: "b"), SubtitleCue(start: 4, end: 6, text: "c")]
        #expect(SubtitleParser.cue(at: 0.5, in: cues) == nil)
        #expect(SubtitleParser.cue(at: 1.5, in: cues)?.text == "a")
        #expect(SubtitleParser.cue(at: 2.5, in: cues) == nil)
        #expect(SubtitleParser.cue(at: 4.5, in: cues)?.text == "c")   // overlap: the later one
        #expect(SubtitleParser.cue(at: 5.5, in: cues)?.text == "c")
    }
}

struct SidecarAndLanguageTests {
    @Test func findsSubtitlesNextToTheVideo() throws {
        let dir = URL.temporaryDirectory.appending(path: "Sidecar-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["Movie.mp4", "Movie.srt", "Movie.en.srt", "Movie.fr.vtt", "Other.srt", "Movie.txt"] {
            try Data().write(to: dir.appending(path: name))
        }
        let files = SidecarSubtitles.find(for: dir.appending(path: "Movie.mp4"))
        #expect(files.map(\.url.lastPathComponent) == ["Movie.en.srt", "Movie.fr.vtt", "Movie.srt"])
        #expect(files.map(\.tag) == ["en", "fr", nil])
        #expect(SidecarSubtitles.describe(files[0]).language == "en")
    }

    @Test func remembersLanguagesAcrossCodeStyles() {
        let tracks = [
            MediaTrack(id: 1, label: "English", language: "eng", isSelected: false),
            MediaTrack(id: 2, label: "French", language: "fr", isSelected: false),
        ]
        #expect(LanguagePreferences.match("fr", in: tracks)?.id == 2)
        #expect(LanguagePreferences.match("en", in: tracks)?.id == 1)     // ISO 639-1 finds 639-2
        #expect(LanguagePreferences.match("off", in: tracks) == nil)
        #expect(LanguagePreferences.match(nil, in: tracks) == nil)
    }

    @Test func speedSteps() {
        #expect(PlayerControls.nextSpeed(after: 1, up: true) == 1.25)
        #expect(PlayerControls.nextSpeed(after: 2, up: true) == 2)
        #expect(PlayerControls.nextSpeed(after: 0.5, up: false) == 0.5)
        #expect(PlayerControls.speedLabel(1.5) == "1.5×")
        #expect(PlayerControls.speedLabel(2) == "2×")
    }

    @Test func subtitleStyleForMPV() {
        let style = SubtitleStyle(size: .large, background: .box, color: .yellow)
        let properties = Dictionary(uniqueKeysWithValues: style.mpvProperties)
        #expect(properties["sub-scale"] == "1.30")
        #expect(properties["sub-border-style"] == "background-box")
        #expect(properties["sub-color"] == "#FFEB59")
    }
}

/// Apple's player engine end to end, on a generated 3 s video with an .srt beside it.
@MainActor
struct AppleEngineTests {
    static func makeVideo(at url: URL, seconds: Int = 3) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64,
        ])
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<(seconds * 10) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            // A solid orange frame (BGRA), so a renderer's output can be checked for real picture.
            CVPixelBufferLockBaseAddress(buffer!, [])
            let base = CVPixelBufferGetBaseAddress(buffer!)!.assumingMemoryBound(to: UInt8.self)
            for row in 0..<64 {
                let line = base + row * CVPixelBufferGetBytesPerRow(buffer!)
                for x in 0..<64 { line[x * 4] = 30; line[x * 4 + 1] = 140; line[x * 4 + 2] = 230; line[x * 4 + 3] = 255 }
            }
            CVPixelBufferUnlockBaseAddress(buffer!, [])
            adaptor.append(buffer!, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 10))
        }
        input.markAsFinished()
        await writer.finishWriting()
        #expect(writer.status == .completed)
    }

    @Test func sidecarSubtitlesShowAtTheRightTimeAndDelay() async throws {
        let dir = URL.temporaryDirectory.appending(path: "Engine-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let video = dir.appending(path: "Clip.mp4")
        try await Self.makeVideo(at: video)
        try "1\n00:00:01,000 --> 00:00:02,000\nHello\n".write(to: dir.appending(path: "Clip.en.srt"), atomically: true, encoding: .utf8)

        let container = try ModelContainer(for: LibrarySource.self, MediaItem.self, WatchRecord.self, SavedMoment.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = LibraryStore(context: container.mainContext)
        let item = MediaItem(key: "test/Clip.mp4", relativePath: "Clip.mp4", collection: "", fileName: "Clip.mp4", fileSize: 1, fileCreatedAt: nil)
        container.mainContext.insert(item)

        let engine = PlaybackSession(item: item, url: video, store: store, startAt: nil)
        defer { engine.end() }
        engine.setPaused(true)
        for _ in 0..<100 where engine.state.subtitleTracks.isEmpty { try await Task.sleep(for: .milliseconds(50)) }
        let track = try #require(engine.state.subtitleTracks.first)
        #expect(track.id == PlaybackSession.sidecarBase)
        #expect(track.language == "en")

        engine.selectSubtitle(track.id)
        engine.seek(to: 1.5)
        #expect(engine.state.subtitleText == "Hello")
        engine.seek(to: 2.5)
        #expect(engine.state.subtitleText == nil)
        engine.setSubtitleDelay(1)            // later: the 1-2 s line now shows at 2-3 s
        #expect(engine.state.subtitleText == "Hello")
        engine.selectSubtitle(nil)
        #expect(engine.state.subtitleText == nil)

        for _ in 0..<100 where engine.state.duration == 0 { try await Task.sleep(for: .milliseconds(50)) }
        #expect(abs(engine.state.duration - 3) < 0.2)
    }
}

/// The MKV Picture in Picture path: mpv switches to CPU rendering, frames come out, and it switches back.
struct SoftwareRendererTests {
    @Test func rendersRealFramesAndHandsVideoBack() async throws {
        let dir = URL.temporaryDirectory.appending(path: "SW-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let video = dir.appending(path: "Clip.mp4")
        try await AppleEngineTests.makeVideo(at: video)

        let mpv = try #require(MPVHandle())
        defer { mpv.destroy() }
        for (name, value) in [("config", "no"), ("terminal", "no"), ("ao", "null"), ("vo", "null"), ("pause", "yes"), ("keep-open", "yes")] {
            mpv.setOption(name, value)
        }
        #expect(mpv.initialize())
        mpv.command(["loadfile", video.path])
        let loadDeadline = Date.now.addingTimeInterval(10)
        while mpv.int("video-params/w") == nil, Date.now < loadDeadline { try await Task.sleep(for: .milliseconds(20)) }

        let renderer = MPVSoftwareRenderer(mpv: mpv)
        #expect(renderer.start())
        var frame: CVPixelBuffer?
        let deadline = Date.now.addingTimeInterval(10)
        while frame == nil, Date.now < deadline {
            frame = renderer.renderFrame(width: 320, height: 180)
            if frame == nil { try await Task.sleep(for: .milliseconds(20)) }
        }
        let pixels = try #require(frame)
        #expect(CVPixelBufferGetWidth(pixels) == 320)
        #expect(mpv.string("current-vo") == "libmpv")

        // The middle of the frame is the video (orange), not a letterbox bar; alpha is opaque.
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        let row = CVPixelBufferGetBaseAddress(pixels)!.assumingMemoryBound(to: UInt8.self) + 90 * CVPixelBufferGetBytesPerRow(pixels)
        let (b, g, r, a) = (Int(row[160 * 4]), Int(row[160 * 4 + 1]), Int(row[160 * 4 + 2]), Int(row[160 * 4 + 3]))
        CVPixelBufferUnlockBaseAddress(pixels, .readOnly)
        #expect(a == 255)
        #expect(abs(r - 230) < 30 && abs(g - 140) < 30 && abs(b - 30) < 30, "got r\(r) g\(g) b\(b)")

        renderer.stop(restoring: "null")
        #expect(!renderer.isRunning)
        #expect(mpv.string("current-vo") != "libmpv")
    }
}
