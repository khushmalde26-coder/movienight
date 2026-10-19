import Foundation

/// User playback settings, stored in UserDefaults. Views read them with @AppStorage(key).
enum PlaybackPreferences {
    /// When on, every video plays from the start instead of resuming. Progress is still recorded,
    /// so turning it off resumes where you left off.
    static let startFromBeginningKey = "startFromBeginning"

    static var startFromBeginning: Bool {
        UserDefaults.standard.bool(forKey: startFromBeginningKey)
    }
}
