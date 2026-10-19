import Foundation
import Security

/// The user's TMDB API Read Access Token, kept in the Keychain (never in the app or its settings).
enum TokenStore {
    private static let service = "movienight.tmdb"
    private static let account = "read-access-token"

    private static func query(dataProtection: Bool) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        #if os(macOS)
        if dataProtection { query[kSecUseDataProtectionKeychain as String] = true }
        #endif
        return query
    }

    static var token: String? {
        for dataProtection in [true, false] {
            var request = query(dataProtection: dataProtection)
            request[kSecReturnData as String] = true
            request[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            if SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
               let data = result as? Data, let token = String(data: data, encoding: .utf8), !token.isEmpty {
                return token
            }
        }
        return nil
    }

    static var hasToken: Bool { token != nil }

    @discardableResult
    static func save(_ token: String) -> Bool {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        delete()
        guard !token.isEmpty else { return true }
        // A build without a signing team can't use the data protection keychain on macOS; fall back.
        for dataProtection in [true, false] {
            var item = query(dataProtection: dataProtection)
            item[kSecValueData as String] = Data(token.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            if SecItemAdd(item as CFDictionary, nil) == errSecSuccess { return true }
        }
        return false
    }

    static func delete() {
        for dataProtection in [true, false] {
            SecItemDelete(query(dataProtection: dataProtection) as CFDictionary)
        }
    }
}
