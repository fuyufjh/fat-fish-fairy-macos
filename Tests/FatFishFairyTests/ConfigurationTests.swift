import Foundation

struct ConfigurationTests {
    static func run() async throws {
        let defaults = APIConfiguration()
        try SmokeTests.check(defaults.baseURL == "https://api.deepseek.com" && defaults.model == "deepseek-flash" && !defaults.thinkingEnabled && defaults.reasoningEffort == .none, "connection defaults")
        let legacy = Data("{\"theme\":\"mint\",\"interval\":60,\"petSize\":180,\"automatic\":false,\"allDisplays\":false,\"personality\":\"hello\",\"credentialPath\":\"/old/.secret\"}".utf8)
        let migrated = try JSONDecoder().decode(Preferences.self, from: legacy)
        try SmokeTests.check(migrated.api == defaults && migrated.theme == "mint" && !migrated.allDisplays, "legacy preferences preserved with new defaults")
        let encoded = String(decoding: try JSONEncoder().encode(migrated), as: UTF8.self)
        try SmokeTests.check(!encoded.contains("credentialPath") && !encoded.contains("secret"), "legacy credential path removed")
        for base in ["https://example.org/v1", "https://example.org/v1/", "https://example.org/v1/chat/completions"] {
            var c = defaults; c.baseURL = base
            let endpoint = try c.endpoint()
            try SmokeTests.check(endpoint.absoluteString == "https://example.org/v1/chat/completions", "custom endpoint normalization")
        }
        for base in ["file:///tmp/api", "https://user:pass@example.org", "https://example.org?key=abc", "https://example.org#fragment", ""] {
            var c = defaults; c.baseURL = base
            try SmokeTests.check((try? c.validated()) == nil, "unsafe or malformed base URL rejected")
        }
        var config = defaults; config.thinkingEnabled = true
        try SmokeTests.check(config.reasoningEffort == .high, "enabling thinking selects high")
        config.thinkingEnabled = false
        try SmokeTests.check(config.reasoningEffort == .none, "disabling thinking selects none")
        let keychain = APIKeyStore(service: "com.fatfishfairy.tests." + UUID().uuidString)
        defer { try? keychain.save(nil, account: "test") }
        let empty = try keychain.load(account: "test")
        try SmokeTests.check(empty == nil, "key defaults empty")
        try keychain.save("fake-key", account: "test")
        let loaded = try keychain.load(account: "test")
        let other = try keychain.load(account: "other-provider")
        try SmokeTests.check(loaded == "fake-key" && other == nil, "keychain provider isolation")
        try keychain.save("replacement", account: "test")
        let replaced = try keychain.load(account: "test")
        try SmokeTests.check(replaced == "replacement", "keychain key replacement")
        try keychain.save(nil, account: "test")
        let removed = try keychain.load(account: "test")
        try SmokeTests.check(removed == nil, "keychain key deletion")
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: sessionConfig)
        defer { session.invalidateAndCancel() }
        let client = DeepSeekClient(session: session)
        for effort in APIConfiguration.Effort.allCases {
            config.baseURL = "https://example.org/v1"; config.model = "custom-vision"; config.reasoningEffort = effort
            StubProtocol.reset([(200, try ResponseRegressionTests.completion("{\"speech\":\"ok\"}"))])
            _ = try await client.respond(key: "fake", configuration: config, personality: "test", memories: [], history: [], text: "test", images: [], observation: false, activities: ["idle"])
            let body = StubProtocol.bodies[0]
            try SmokeTests.check(body["model"] as? String == "custom-vision" && body["reasoning_effort"] as? String == effort.rawValue, "custom model and effort request")
            try SmokeTests.check((body["thinking"] as? [String: String])?["type"] == (effort == .none ? "disabled" : "enabled"), "consistent thinking request")
            try SmokeTests.check(StubProtocol.urls.first == "https://example.org/v1/chat/completions" && StubProtocol.authorizations.first == "Bearer fake", "custom URL and authorization")
        }
    }
}
