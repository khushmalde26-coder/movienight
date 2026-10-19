import AVFoundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// Generated artwork, cached as JPEGs in Caches so the system can purge it.
enum ThumbnailService {
    static var directory: URL {
        let dir = URL.cachesDirectory.appending(path: "Thumbnails", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func fileName(for key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined() + ".jpg"
    }

    /// Grabs a frame 10% in: the first frame of home video is often black or a blur of a pocket.
    /// TODO(phase 2): sample several frames and keep the sharpest, best-exposed one.
    static func generate(for url: URL, key: String, duration: Double?) async -> String? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 720)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 2, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 2, preferredTimescale: 600)

        let time = CMTime(seconds: (duration ?? 0) * 0.1, preferredTimescale: 600)
        guard let image = try? await generator.image(at: time).image else { return nil }

        return write(image, key: key)
    }

    /// Downscales a frame grabbed by MPVProbe and stores it as the item's artwork.
    static func store(frameAt url: URL, key: String) -> String? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 1280,
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options)
        else { return nil }
        return write(image, key: key)
    }

    private static func write(_ image: CGImage, key: String) -> String? {
        let name = fileName(for: key)
        let destinationURL = directory.appending(path: name)
        guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? name : nil
    }

    /// Pass `maxPixelSize` for cards: decoding every 1280px thumbnail at full size costs ~3.5MB each.
    static func load(_ name: String, maxPixelSize: Int? = nil) -> CGImage? {
        let url = directory.appending(path: name)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        guard let maxPixelSize else { return CGImageSourceCreateImageAtIndex(source, 0, nil) }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    /// The system purges Caches under storage pressure, so artwork can vanish and must be remade.
    static func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: directory.appending(path: name).path)
    }
}
