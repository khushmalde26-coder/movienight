import Foundation
import Testing
@testable import MovieNight

struct VideoQualityTests {
    @Test(arguments: [
        (3840, 2160, "4K"), (2160, 3840, "4K"), (3840, 1600, "4K"),
        (1920, 1080, "HD"), (1080, 1920, "HD"), (1280, 720, "HD"),
        (720, 480, "SD"), (640, 360, "SD"),
    ])
    func resolutionBadge(width: Int, height: Int, expected: String) {
        #expect(VideoQuality(width: width, height: height).resolutionBadge == expected)
    }

    @Test func badgesListNotableTraitsInOrder() {
        let phone = VideoQuality(width: 2160, height: 3840, frameRate: 59.94, isHDR: true)
        #expect(phone.badges == ["4K", "HDR", "60fps", "Vertical"])
        let film = VideoQuality(width: 1920, height: 800, frameRate: 23.976)
        #expect(film.badges == ["HD"])
        #expect(film.resolutionName == "1080p")
    }

    @Test func dolbyVisionReplacesHDR() {
        let clip = VideoQuality(width: 3840, height: 2160, isHDR: true, isDolbyVision: true)
        #expect(clip.badges == ["4K", "Dolby Vision"])
    }

    @Test func audioAndBitrateLabels() {
        #expect(VideoQuality.audioLabel(channels: 2) == "Stereo")
        #expect(VideoQuality.audioLabel(channels: 6) == "5.1")
        #expect(VideoQuality.audioLabel(channels: nil) == nil)
        #expect(VideoQuality.bitrateLabel(fileSize: 100_000_000, duration: 80) == "10 Mbps")
        #expect(VideoQuality.bitrateLabel(fileSize: 5_000_000, duration: 10) == "4.0 Mbps")
    }

    @Test func codecNames() {
        #expect(CodecName.fromFourCC("hvc1") == "HEVC")
        #expect(CodecName.fromFFmpeg("rv40") == "RealVideo")
        #expect(CodecName.fromFFmpeg("mpeg2video") == "MPEG-2")
        #expect(CodecName.fromFFmpeg("weird") == "WEIRD")
    }

    @Test func durationFormatting() {
        #expect(Formatters.duration(45) == "45s")
        #expect(Formatters.duration(192) == "3m 12s")
        #expect(Formatters.duration(1500) == "25m")
        #expect(Formatters.duration(5520) == "1h 32m")
        #expect(Formatters.remaining(1920) == "32m left")
        #expect(Formatters.clock(3723) == "1:02:03")
        #expect(Formatters.clock(245) == "4:05")
    }

    @Test func scannerKnowsMatroskaAndFriends() {
        for ext in ["mkv", "webm", "avi", "wmv", "flv", "vob", "rmvb", "mxf", "ogv", "m2ts"] {
            #expect(LibraryScanner.videoExtensions.contains(ext))
        }
        #expect(!LibraryScanner.videoExtensions.contains("m4p"))
    }
}
