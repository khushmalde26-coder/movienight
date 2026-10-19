import Foundation
import Libmpv

/// Thin Swift wrapper over a libmpv client handle. The mpv client API is thread-safe,
/// so these can be called from any thread; only event draining needs a single consumer.
final class MPVHandle: @unchecked Sendable {
    let raw: OpaquePointer

    init?() {
        guard let handle = mpv_create() else { return nil }
        raw = handle
    }

    func setOption(_ name: String, _ value: String) {
        mpv_set_option_string(raw, name, value)
    }

    func initialize() -> Bool {
        mpv_initialize(raw) >= 0
    }

    func command(_ args: [String]) {
        var cargs: [UnsafePointer<CChar>?] = args.map { UnsafePointer(strdup($0)) } + [nil]
        defer { for arg in cargs { free(UnsafeMutablePointer(mutating: arg)) } }
        mpv_command(raw, &cargs)
    }

    func setProperty(_ name: String, _ value: String) {
        mpv_set_property_string(raw, name, value)
    }

    func string(_ name: String) -> String? {
        guard let value = mpv_get_property_string(raw, name) else { return nil }
        defer { mpv_free(value) }
        return String(cString: value)
    }

    func double(_ name: String) -> Double? {
        var value = 0.0
        return mpv_get_property(raw, name, MPV_FORMAT_DOUBLE, &value) >= 0 ? value : nil
    }

    func int(_ name: String) -> Int? {
        var value: Int64 = 0
        return mpv_get_property(raw, name, MPV_FORMAT_INT64, &value) >= 0 ? Int(value) : nil
    }

    func flag(_ name: String) -> Bool? {
        var value: Int32 = 0
        return mpv_get_property(raw, name, MPV_FORMAT_FLAG, &value) >= 0 ? value != 0 : nil
    }

    func destroy() {
        mpv_terminate_destroy(raw)
    }
}
