import Foundation

/// Human labels for the technical facts in a file. Pure, so it's unit tested.
struct VideoQuality: Sendable, Hashable {
    var width: Int
    var height: Int
    var frameRate: Double?
    var isHDR: Bool = false
    var isDolbyVision: Bool = false

    var isVertical: Bool { height > width }

    /// Classified on the long and short edge, so vertical 2160×3840 phone video still counts as 4K
    /// and letterboxed 3840×1600 film rips aren't demoted.
    var resolutionBadge: String {
        let long = max(width, height), short = min(width, height)
        if long >= 3800 || short >= 2100 { return "4K" }
        if long >= 1260 || short >= 700 { return "HD" }
        return "SD"
    }

    /// "1080p", "2160p": the precise version for the detail page.
    var resolutionName: String {
        let long = max(width, height), short = min(width, height)
        switch (long, short) {
        case (3800..., _), (_, 2100...): return "4K"
        case (2500..., _), (_, 1400...): return "1440p"
        case (1900..., _), (_, 1060...): return "1080p"
        case (1260..., _), (_, 700...): return "720p"
        default: return "\(short)p"
        }
    }

    var isHighFrameRate: Bool { (frameRate ?? 0) >= 48 }

    /// Short labels for cards and the hero, most important first.
    var badges: [String] {
        var result = [resolutionBadge]
        if isDolbyVision { result.append("Dolby Vision") } else if isHDR { result.append("HDR") }
        if isHighFrameRate, let frameRate { result.append("\(Int(frameRate.rounded()))fps") }
        if isVertical { result.append("Vertical") }
        return result
    }

    static func audioLabel(channels: Int?) -> String? {
        switch channels {
        case nil, 0: nil
        case 1: "Mono"
        case 2: "Stereo"
        case 6: "5.1"
        case 8: "7.1"
        case let n?: "\(n) channels"
        }
    }

    static func bitrateLabel(fileSize: Int64, duration: Double?) -> String? {
        guard let duration, duration > 1, fileSize > 0 else { return nil }
        let mbps = Double(fileSize) * 8 / duration / 1_000_000
        return mbps >= 10 ? "\(Int(mbps.rounded())) Mbps" : String(format: "%.1f Mbps", mbps)
    }
}

/// Friendly codec names from AVFoundation four-character codes and FFmpeg codec ids.
enum CodecName {
    static func fromFourCC(_ fourCC: String) -> String {
        switch fourCC {
        case "avc1", "avc3": "H.264"
        case "hvc1", "hev1": "HEVC"
        case "dvh1", "dvhe", "dva1", "dvav": "Dolby Vision"
        case "av01": "AV1"
        case "vp09": "VP9"
        case "ap4h", "ap4x", "apch", "apcn", "apcs", "apco": "ProRes"
        case "mp4v": "MPEG-4"
        case "jpeg": "Motion JPEG"
        default: fourCC.trimmingCharacters(in: .whitespaces).uppercased()
        }
    }

    static func fromFFmpeg(_ id: String) -> String {
        switch id.lowercased() {
        case "h264": "H.264"
        case "hevc": "HEVC"
        case "av1": "AV1"
        case "vp8": "VP8"
        case "vp9": "VP9"
        case "mpeg1video": "MPEG-1"
        case "mpeg2video": "MPEG-2"
        case "mpeg4": "MPEG-4"
        case "msmpeg4v1", "msmpeg4v2", "msmpeg4v3": "DivX 3"
        case "wmv1", "wmv2", "wmv3": "Windows Media Video"
        case "vc1": "VC-1"
        case "rv10", "rv20", "rv30", "rv40": "RealVideo"
        case "prores": "ProRes"
        case "mjpeg": "Motion JPEG"
        case "theora": "Theora"
        case "flv1": "Sorenson Spark"
        case "vp6", "vp6f", "vp6a": "VP6"
        case "h263": "H.263"
        case "dirac": "Dirac"
        case "dnxhd": "DNxHD"
        case "roq": "RoQ"
        case "amv": "AMV"
        default: id.uppercased()
        }
    }
}
