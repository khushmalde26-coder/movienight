import Foundation

/// User playback settings, stored in UserDefaults. Views read them with @AppStorage(key);
/// players read the static accessors when they start, and live while sound settings change.
enum PlaybackPreferences {
    /// When on, every video plays from the start instead of resuming. Progress is still recorded,
    /// so turning it off resumes where you left off.
    static let startFromBeginningKey = "startFromBeginning"
    static let videoQualityKey = "videoQuality"
    static let dialogueBoostKey = "dialogueBoost"
    static let nightModeKey = "nightMode"
    static let balanceKey = "audioBalance"

    static var startFromBeginning: Bool {
        UserDefaults.standard.bool(forKey: startFromBeginningKey)
    }

    static var videoQuality: VideoQualityMode {
        UserDefaults.standard.string(forKey: videoQualityKey).flatMap(VideoQualityMode.init(rawValue:)) ?? .standard
    }

    static var sound: SoundSettings {
        let defaults = UserDefaults.standard
        return SoundSettings(
            dialogueBoost: defaults.bool(forKey: dialogueBoostKey),
            nightMode: defaults.bool(forKey: nightModeKey),
            balance: defaults.double(forKey: balanceKey)
        )
    }

    static func apply(_ preset: PlaybackPreset) {
        let defaults = UserDefaults.standard
        defaults.set(preset.videoQuality.rawValue, forKey: videoQualityKey)
        defaults.set(preset.sound.dialogueBoost, forKey: dialogueBoostKey)
        defaults.set(preset.sound.nightMode, forKey: nightModeKey)
    }
}

/// How hard the extended (mpv) player works on picture quality. Apple's player always decodes in
/// hardware at full quality, so this only changes MKV and the other extended formats.
enum VideoQualityMode: String, CaseIterable, Identifiable, Sendable {
    case best, standard, efficient
    var id: Self { self }

    var title: String {
        switch self {
        case .best: "Best"
        case .standard: "Standard"
        case .efficient: "Efficient"
        }
    }

    /// mpv properties, settable before or during playback.
    var mpvProperties: [(String, String)] {
        switch self {
        case .best:
            [("scale", "ewa_lanczossharp"), ("cscale", "ewa_lanczossharp"), ("dscale", "mitchell"), ("deband", "yes"), ("dither-depth", "auto")]
        case .standard:
            [("scale", "spline36"), ("cscale", "spline36"), ("dscale", "mitchell"), ("deband", "no"), ("dither-depth", "auto")]
        case .efficient:
            [("scale", "bilinear"), ("cscale", "bilinear"), ("dscale", "bilinear"), ("deband", "no"), ("dither-depth", "no")]
        }
    }
}

/// Dialogue, loudness and balance. Applied by both players.
struct SoundSettings: Equatable, Sendable {
    var dialogueBoost = false
    /// Evens out loud and quiet scenes, for watching late or with others asleep.
    var nightMode = false
    /// -1 is all left, 1 is all right.
    var balance: Double = 0

    var isNeutral: Bool { !dialogueBoost && !nightMode && abs(balance) < 0.01 }

    /// Left and right gains for a balance: the far side fades out, the near side stays at full level.
    static func balanceGains(_ balance: Double) -> (left: Float, right: Float) {
        let b = Float(min(max(balance, -1), 1))
        return (min(1, 1 - b), min(1, 1 + b))
    }

    /// The same effects as an mpv `af` chain. MPVKit's FFmpeg has equalizer, pan, aformat and volume
    /// but no compressor, so night mode there softens bass rumble and lifts speech instead of
    /// compressing. Empty means no filters.
    var mpvAudioFilter: String {
        var filters: [String] = []
        if dialogueBoost || nightMode {
            // Speech presence band; a little headroom first so the boost doesn't clip.
            filters.append("volume=volume=\(dialogueBoost ? "-4dB" : "-2dB")")
            filters.append("equalizer=f=2500:t=q:w=0.9:g=\(dialogueBoost ? 6 : 3)")
        }
        if nightMode {
            filters.append("equalizer=f=70:t=q:w=0.7:g=-9")
        }
        if abs(balance) >= 0.01 {
            let (left, right) = Self.balanceGains(balance)
            filters.append("aformat=channel_layouts=stereo")
            filters.append(String(format: "pan=stereo|c0=%.3f*c0|c1=%.3f*c1", left, right))
        }
        return filters.isEmpty ? "" : "lavfi=[" + filters.joined(separator: ",") + "]"
    }
}

/// One-tap bundles of the detailed settings above.
enum PlaybackPreset: String, CaseIterable, Identifiable, Sendable {
    case standard, bestQuality, saveBattery, quietRoom
    var id: Self { self }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .bestQuality: "Best Quality"
        case .saveBattery: "Save Battery"
        case .quietRoom: "Quiet Room"
        }
    }

    var summary: String {
        switch self {
        case .standard: "Good picture, normal sound."
        case .bestQuality: "Sharpest scaling and smooth gradients. Uses more power."
        case .saveBattery: "Simpler picture processing for long trips."
        case .quietRoom: "Clearer dialogue and gentler loud scenes."
        }
    }

    var videoQuality: VideoQualityMode {
        switch self {
        case .standard, .quietRoom: .standard
        case .bestQuality: .best
        case .saveBattery: .efficient
        }
    }

    var sound: SoundSettings {
        self == .quietRoom ? SoundSettings(dialogueBoost: true, nightMode: true) : SoundSettings()
    }

    /// The preset these settings amount to, or nil when they've been customised. Balance is left
    /// out: it's about the room or your ears, not the mood.
    static func matching(videoQuality: VideoQualityMode, dialogueBoost: Bool, nightMode: Bool) -> PlaybackPreset? {
        allCases.first {
            $0.videoQuality == videoQuality && $0.sound.dialogueBoost == dialogueBoost && $0.sound.nightMode == nightMode
        }
    }
}
