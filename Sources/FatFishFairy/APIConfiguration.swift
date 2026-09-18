import Foundation

struct APIConfiguration: Codable, Equatable {
    enum Effort: String, Codable, CaseIterable { case none, low, high, max }
    var baseURL = "https://api.deepseek.com"
    var apiKey = ""
    var model = "deepseek-flash"
    var reasoningEffort: Effort = .none
    var thinkingEnabled: Bool {
        get { reasoningEffort != .none }
        set { reasoningEffort = newValue ? (reasoningEffort == .none ? .high : reasoningEffort) : .none }
    }

    enum CodingKeys: String, CodingKey { case baseURL, model, apiKey, reasoningEffort }
    init() {}
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try values.decodeIfPresent(String.self, forKey: .baseURL) ?? baseURL
        model = try values.decodeIfPresent(String.self, forKey: .model) ?? model
        apiKey = try values.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        reasoningEffort = try values.decodeIfPresent(Effort.self, forKey: .reasoningEffort) ?? .none
    }

    func validated() throws -> Self {
        var result = self
        result.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while result.baseURL.hasSuffix("/") { result.baseURL.removeLast() }
        result.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
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
