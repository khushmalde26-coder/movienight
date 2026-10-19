import Foundation
import Testing
@testable import MovieNight

struct DisplayTitleTests {
    private let date = ISO8601DateFormatter().date(from: "2019-07-14T15:30:00Z")!
    private let locale = Locale(identifier: "en_GB")

    @Test(arguments: ["IMG_4821.MOV", "PXL_20230712_181502123.mp4", "20190714_153012.mp4", "GOPR0042.MP4", "C0042.MP4", "DJI_0007.MOV"])
    func cameraNamesBecomeDates(fileName: String) {
        let title = DisplayTitle.make(fileName: fileName, recordedAt: date, locale: locale)
        #expect(title.contains("2019"))
        #expect(title.contains("July"))
    }

    @Test func meaningfulNamesAreKept() {
        #expect(DisplayTitle.make(fileName: "Grandma's 80th_speech.mov", recordedAt: date) == "Grandma's 80th speech")
        #expect(DisplayTitle.make(fileName: "The.Matrix.1999.mkv", recordedAt: nil) == "The Matrix 1999")
    }

    @Test func cameraNameWithoutDateFallsBackToCleanName() {
        #expect(DisplayTitle.make(fileName: "IMG_4821.MOV", recordedAt: nil) == "IMG 4821")
    }
}
