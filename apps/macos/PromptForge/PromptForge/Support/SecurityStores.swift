import Foundation
import Security

enum KeychainSecretStore {
    private static let service = "com.lunarmothstudios.PromptForge"
    private static let secretKeys = ["OPENAI_API_KEY", "OPENROUTER_API_KEY"]

    static func hydrate(environment: inout [String: String]) {
        for key in secretKeys {
            if let stored = read(key: key), !stored.isEmpty {
                environment[key] = stored
                continue
            }
            guard let inherited = environment[key], !inherited.isEmpty else {
                continue
            }
            _ = write(key: key, value: inherited)
        }
    }

    static func has(key: String) -> Bool {
        guard let value = read(key: key) else {
            return false
        }
        return !value.isEmpty
    }

    static func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func write(key: String, value: String) -> Bool {
        let payload = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: payload,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        if updateStatus != errSecItemNotFound {
            return false
        }
        var insert = query
        insert[kSecValueData as String] = payload
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

enum SecurityScopedProjectStore {
    private static let bookmarkKey = "PromptForgeProjectBookmark"
    private static let pathKey = "PromptForgeProjectPath"

    static func save(url: URL) {
        guard let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else {
            UserDefaults.standard.set(url.path, forKey: pathKey)
            return
        }
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        UserDefaults.standard.set(url.path, forKey: pathKey)
    }

    static func resolve() -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else {
            return nil
        }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        if isStale {
            save(url: url)
        }
        return url
    }

    static func savedPath() -> String? {
        UserDefaults.standard.string(forKey: pathKey)
    }
}
