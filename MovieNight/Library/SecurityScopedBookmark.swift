import Foundation

/// Persistent access to folders the user picked (iCloud Drive, external drives, anywhere).
/// macOS needs an explicit security scope; iOS bookmarks from the document picker carry it implicitly.
enum SecurityScopedBookmark {
    static func make(for url: URL) throws -> Data {
        #if os(macOS)
        try url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #else
        try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
    }

    static func resolve(_ data: Data) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        #if os(macOS)
        let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &isStale)
        #else
        let url = try URL(resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &isStale)
        #endif
        return (url, isStale)
    }
}
