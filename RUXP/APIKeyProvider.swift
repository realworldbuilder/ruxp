import Foundation
import Security

enum APIKeyProvider {
    private static let keychainService = "com.whussey.ruxp.openai"
    private static let keychainAccount = "custom_api_key"

    enum KeySource { case custom, bundled, none }

    /// Key baked in at build time from Config/Secrets.xcconfig via Info.plist.
    /// Nil when the file was absent (BYOK mode) or the variable never expanded.
    static var bundledKey: String? {
        guard let raw = Bundle.main.infoDictionary?["RUXPOpenAIKey"] as? String else { return nil }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains("$(") else { return nil }
        return key
    }

    /// The user's own key from the Keychain. Overrides the bundled one.
    static var customKey: String? {
        loadKeychainKey().flatMap { $0.isEmpty ? nil : $0 }
    }

    static var keySource: KeySource {
        if customKey != nil { return .custom }
        if bundledKey != nil { return .bundled }
        return .none
    }

    static var hasBundledKey: Bool { bundledKey != nil }

    /// Custom key, else bundled key, else "".
    static var resolvedKey: String {
        customKey ?? bundledKey ?? ""
    }

    static var hasKey: Bool {
        !resolvedKey.isEmpty
    }

    /// e.g. "sk-…abcd" for display in Settings. Custom key only; the bundled key is never shown.
    static var maskedKey: String? {
        guard let key = customKey, key.count >= 8 else { return nil }
        return "\(key.prefix(3))…\(key.suffix(4))"
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return false }

        delete()

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data
        ]
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func loadKeychainKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
