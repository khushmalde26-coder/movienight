import Foundation

/// Object-based surround: sound placed around and above you rather than in fixed channels.
enum SpatialAudio: String, Codable, Sendable, CaseIterable {
    case atmos, dtsX

    /// The chip's symbol: sound radiating around you. (Dolby's and DTS's own logos need a licence.)
    static let symbol = "dot.radiowaves.left.and.right"

    /// Chip text, short enough for a card.
    var badge: String {
        switch self {
        case .atmos: "Atmos"
        case .dtsX: "DTS:X"
        }
    }

    var spoken: String {
        switch self {
        case .atmos: "Dolby Atmos"
        case .dtsX: "DTS:X"
        }
    }

    /// FFmpeg's codec profile, as mpv reports it: "Dolby Digital Plus + Dolby Atmos",
    /// "Dolby TrueHD + Dolby Atmos", "DTS-HD MA + DTS:X", "DTS-HD MA + DTS:X IMAX".
    static func fromProfile(_ profile: String?) -> SpatialAudio? {
        guard let profile else { return nil }
        if profile.localizedCaseInsensitiveContains("atmos") { return .atmos }
        if profile.localizedCaseInsensitiveContains("DTS:X") { return .dtsX }
        return nil
    }

    /// Release names often say so ("…DDP5.1.Atmos", "…TrueHD.7.1.Atmos", "…DTS-X…"): the fallback
    /// for files whose soundtrack couldn't be read.
    static func fromFileName(_ fileName: String) -> SpatialAudio? {
        let text = fileName.replacingOccurrences(of: #"[._]"#, with: " ", options: .regularExpression)
        if text.range(of: #"(?i)\batmos\b"#, options: .regularExpression) != nil { return .atmos }
        if text.range(of: #"(?i)\bdts[ :-]?x\b"#, options: .regularExpression) != nil { return .dtsX }
        return nil
    }

    /// Dolby Digital Plus carries Atmos as Joint Object Coding, flagged in the MP4 'dec3' box
    /// (ETSI TS 102 366 annex F: flag_ec3_extension_type_a after the substream list).
    static func isJointObjectCoding(dec3: Data) -> Bool {
        var reader = BitReader(dec3)
        guard reader.read(13) != nil, let independent = reader.read(3) else { return false }
        for _ in 0...independent {
            // fscod, bsid, reserved, asvc, bsmod, acmod, lfeon, reserved, num_dep_sub
            guard reader.read(23) != nil, let dependents = reader.read(4) else { return false }
            guard reader.read(dependents > 0 ? 9 : 1) != nil else { return false }
        }
        guard reader.read(7) != nil, let flag = reader.read(1) else { return false }
        return flag == 1
    }
}

/// Reads big-endian bit fields; nil once the data runs out.
private struct BitReader {
    private let bytes: [UInt8]
    private var position = 0

    init(_ data: Data) { bytes = [UInt8](data) }

    mutating func read(_ count: Int) -> Int? {
        guard position + count <= bytes.count * 8 else { return nil }
        var value = 0
        for _ in 0..<count {
            let bit = (bytes[position / 8] >> (7 - UInt8(position % 8))) & 1
            value = value << 1 | Int(bit)
            position += 1
        }
        return value
    }
}
