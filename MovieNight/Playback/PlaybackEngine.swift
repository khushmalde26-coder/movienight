/// Which player opens a file. AVKit is preferred because it brings PiP, AirPlay and the system
/// controls; mpv (FFmpeg) covers everything AVFoundation can't: MKV, AVI, WMV, FLV, RealMedia, VOB...
enum PlaybackEngine: String, Sendable {
    case avKit = "avkit"
    case mpv = "mpv"
}
