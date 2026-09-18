import Foundation
import Security

struct APIConfiguration: Codable, Equatable {
    enum Effort: String, Codable, CaseIterable { case none, low, high, max }
    var baseURL = "https://api.deepseek.com"
    var model = "deepseek-flash"
    var reasoningEffort: Effort = .none
    var thinkingEnabled: Bool {
        get { reasoningEffort != .none }
        set { reasoningEffort = newValue ? (reasoningEffort == .none ? .high : reasoningEffort) : .none }
    }

    func validated() throws -> Self {
        var result = self
        result.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while result.baseURL.hasSuffix("/") { result.baseURL.removeLast() }
        result.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: result.baseURL),
              ["https", "http"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil, parts.url != nil else {
            throw FishError.message("Base URL 必须是有效的 HTTP(S) 地址，不能包含账号、密码、查询参数或片段。")
        }
        guard !result.model.isEmpty else { throw FishError.message("请填写模型名称。") }
        return result
    }

    func endpoint() throws -> URL {
        let base = try validated().baseURL
        return URL(string: base.hasSuffix("/chat/completions") ? base : base + "/chat/completions")!
    }
}

struct APIKeyStore {
    var service = "com.fatfishfairy.macos.api-key"
    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    func load(account: String) throws -> String? {
        var query = query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }
    func save(_ key: String?, account: String) throws {
        let query = query(account)
        guard let key, !key.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecItemNotFound { try check(status) }
            return
        }
        let values = [kSecValueData as String: Data(key.utf8)]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var item = query.merging(values) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            try check(SecItemAdd(item as CFDictionary, nil))
        } else { try check(status) }
    }
    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw FishError.message("钥匙串访问失败（\(status)），请检查 macOS 钥匙串权限后重试。") }
    }
}
