import Foundation
import Security

public enum KeychainService {
    private static let serviceName = "sh.instabox.mac-manager.apikeys"
    private static let profilesDefaultsKey = "instabox.savedProfiles.v1"
    private static let activeProfileDefaultsKey = "instabox.activeProfileId.v1"

    public static func saveAPIKey(_ apiKey: String, for profileID: UUID) throws {
        let account = profileID.uuidString
        let data = Data(apiKey.utf8)

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "无法保存 API Key 到 macOS 钥匙串（错误码 \(status)）"
            ])
        }
    }

    public static func loadAPIKey(for profileID: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: profileID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        return key
    }

    public static func deleteAPIKey(for profileID: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: profileID.uuidString
        ]
        SecItemDelete(query as CFDictionary)
    }

    public static func loadProfiles() -> [APIProfile] {
        guard let data = UserDefaults.standard.data(forKey: profilesDefaultsKey),
              let profiles = try? JSONDecoder().decode([APIProfile].self, from: data) else {
            return []
        }
        return profiles
    }

    public static func saveProfiles(_ profiles: [APIProfile]) {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: profilesDefaultsKey)
        }
    }

    public static func loadActiveProfileID() -> UUID? {
        guard let str = UserDefaults.standard.string(forKey: activeProfileDefaultsKey) else {
            return nil
        }
        return UUID(uuidString: str)
    }

    public static func saveActiveProfileID(_ id: UUID?) {
        if let id {
            UserDefaults.standard.set(id.uuidString, forKey: activeProfileDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: activeProfileDefaultsKey)
        }
    }

    public static func maskKey(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 12 else { return String(trimmed.prefix(6)) + "••••" }
        return "\(trimmed.prefix(8))••••\(trimmed.suffix(4))"
    }
}
