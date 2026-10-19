import Foundation
import Testing
@testable import MovieNight

struct LibraryScannerTests {
    private func makeFolder(_ files: [String]) throws -> URL {
        let root = URL.temporaryDirectory.appending(path: "ScannerTest-\(UUID().uuidString)")
        for file in files {
            let url = root.appending(path: file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([0, 1, 2]).write(to: url)
        }
        return root
    }

    @Test func findsVideosAndCollections() async throws {
        let root = try makeFolder([
            "Holidays/Japan/IMG_0001.MOV", "Holidays/clip.mkv", "loose.mp4",
            "notes.txt", ".hidden/secret.mp4",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let files = try await LibraryScanner().scan(root: root)
        let byPath = Dictionary(uniqueKeysWithValues: files.map { ($0.relativePath, $0) })
        #expect(Set(byPath.keys) == ["Holidays/Japan/IMG_0001.MOV", "Holidays/clip.mkv", "loose.mp4"])
        #expect(byPath["Holidays/Japan/IMG_0001.MOV"]?.collection == "Holidays")
        #expect(byPath["loose.mp4"]?.collection == "")
        #expect(byPath["loose.mp4"]?.isLocal == true)
    }

    @Test func evictedICloudPlaceholdersUseTheRealName() async throws {
        let root = try makeFolder(["Trip/.IMG_0002.MOV.icloud"])
        defer { try? FileManager.default.removeItem(at: root) }

        let files = try await LibraryScanner().scan(root: root)
        #expect(files.map(\.relativePath) == ["Trip/IMG_0002.MOV"])
        #expect(files.first?.isLocal == false)
    }

    /// An unplugged drive must never look like an empty folder, or the library would be wiped.
    @Test func missingFolderThrowsInsteadOfReturningNothing() async {
        let missing = URL.temporaryDirectory.appending(path: "NotThere-\(UUID().uuidString)")
        await #expect(throws: (any Error).self) {
            try await LibraryScanner().scan(root: missing)
        }
    }
}
