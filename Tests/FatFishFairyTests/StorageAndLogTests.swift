import Foundation

struct StorageAndLogTests {
    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var legacy = SavedState()
        var config = APIConfiguration(); config.apiKey = "migration-fake-key"
        legacy.preferences.systemPrompt = "custom-system {{mode}} {{activities}}"
        legacy.preferences.connection = config; legacy.preferences.theme = "custom-theme"
        legacy.memories = [FishMemory(text: "喜欢咖啡")]
        // Equal dates ensure pagination uses a stable sequence, not timestamps.
        legacy.messages = (0..<137).map { ChatMessage(role: "user", text: "message \($0)", date: Date(timeIntervalSince1970: 100), observation: $0 % 2 == 0) }
        let store = StateStore(directory: root)
        let original = try JSONEncoder().encode(legacy)
        try original.write(to: store.legacyFile)
        var loaded = try store.load()
        try SmokeTests.check(loaded.messages.count == 50 && loaded.messages.first?.text == "message 87" && loaded.messages.last?.text == "message 136", "migration loads latest 50 in chronological order")
        try SmokeTests.check(loaded.preferences.api.apiKey == config.apiKey && loaded.preferences.theme == "custom-theme" && loaded.memories.first?.text == "喜欢咖啡", "migration retains configuration, theme and memories")
        try SmokeTests.check(loaded.preferences.systemPrompt == legacy.preferences.systemPrompt, "custom system prompt survives migration")
        let custom = try PromptBuilder.messages(systemPrompt: loaded.preferences.systemPrompt, character: "custom-character", memories: [], activities: ["idle"], example: "{}", observation: true)
        try SmokeTests.check((custom[0]["content"] as! String).contains("custom-system") && (custom[0]["content"] as! String).contains("观察屏幕") && (custom[1]["content"] as! String).contains("custom-character"), "edited system prompt used separately from persona")
        let backup = try Data(contentsOf: store.legacyFile)
        try SmokeTests.check(backup == original, "legacy backup preserved byte-for-byte")
        let second = try store.messagePage(before: loaded.messages.first?.id)
        let third = try store.messagePage(before: second.first?.id)
        let hasOlder = try store.hasMessages(before: third.first?.id)
        try SmokeTests.check(second.count == 50 && third.count == 37 && !hasOlder, "50 item pages handle equal timestamps and oldest boundary")
        try SmokeTests.check((third + second + loaded.messages).map(\.id) == legacy.messages.map(\.id), "pagination has no duplicate or missing messages")
        loaded.messages.append(ChatMessage(role: "assistant", text: "new reply"))
        loaded.memories = []
        try store.save(loaded)
        try store.save(loaded)
        let reopened = try StateStore(directory: root).load()
        let older = try store.messagePage(before: reopened.messages.first?.id, limit: 500)
        try SmokeTests.check(reopened.messages.count == 50 && older.count == 88 && reopened.messages.last?.text == "new reply", "partial-page save preserves full history and deduplicates")
        try SmokeTests.check(reopened.memories.isEmpty, "deleted memory is not resurrected from legacy JSON")
        let invalidRoot = root.appendingPathComponent("bad-json")
        try FileManager.default.createDirectory(at: invalidRoot, withIntermediateDirectories: true)
        let invalid = StateStore(directory: invalidRoot)
        try Data("broken".utf8).write(to: invalid.legacyFile)
        try SmokeTests.check((try? invalid.load()) == nil, "invalid legacy state blocks migration")
        try original.write(to: invalid.legacyFile)
        let recovered = try invalid.load()
        try SmokeTests.check(recovered.messages.count == 50, "failed migration is retryable without partial import")

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: sessionConfig)
        defer { session.invalidateAndCancel() }
        let logURL = root.appendingPathComponent("app.log")
        let client = DeepSeekClient(session: session, logURL: logURL)
        let secret = "fake-sensitive-key"
        StubProtocol.reset([(200, try ResponseRegressionTests.completion("{}")), (200, try ResponseRegressionTests.completion("{\"speech\":\"ok\"}"))])
        _ = try await client.respond(key: secret, personality: "character-only-marker", memories: [], history: [], text: "hello " + secret, images: [Data([1,2,3])], observation: false, activities: ["idle"])
        let log = try String(contentsOf: logURL, encoding: .utf8)
        let events = try log.split(separator: "\n").map { try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
        try SmokeTests.check(events.count == 4 && events.compactMap { $0["event"] as? String } == ["request", "response", "request", "response"], "every retry logs request and response")
        try SmokeTests.check(!log.contains(secret) && log.contains("[REDACTED]") && log.contains("base64,AQID"), "request bodies include images but redact API key")
        try SmokeTests.check(events[0]["request_id"] as? String == events[3]["request_id"] as? String && events[2]["attempt"] as? Int == 2, "log correlation and attempt numbers")
        let body = events[0]["body"] as! [String: Any]
        let messages = body["messages"] as! [[String: Any]]
        try SmokeTests.check(!(messages[0]["content"] as! String).contains("character-only-marker") && (messages[1]["content"] as! String).contains("character-only-marker"), "system rules and persona are separate messages")
        try SmokeTests.check(!(messages[0]["content"] as! String).contains("{{") && (messages[0]["content"] as! String).contains("当前本地日期和时间"), "system template resolves runtime context")
        StubProtocol.reset([(401, Data("unauthorized".utf8))])
        do {
            _ = try await client.respond(key: secret, personality: "test", memories: [], history: [], text: "test", images: [], observation: false, activities: ["idle"])
            throw FishError.message("FAIL: expected HTTP error")
        } catch let error as FishError { try SmokeTests.check(error.localizedDescription.contains("密钥"), "HTTP error preserved") }
        let failedLog = try String(contentsOf: logURL, encoding: .utf8)
        try SmokeTests.check(failedLog.contains("unauthorized") && failedLog.contains("401"), "HTTP error response logged before parsing")
        StubProtocol.reset([])
        StubProtocol.transportError = URLError(.notConnectedToInternet)
        do {
            _ = try await client.respond(key: secret, personality: "test", memories: [], history: [], text: "test", images: [], observation: false, activities: ["idle"])
            throw FishError.message("FAIL: expected transport error")
        } catch is URLError {}
        let transportLog = try String(contentsOf: logURL, encoding: .utf8)
        try SmokeTests.check(transportLog.contains("\"event\":\"error\""), "transport failures logged")
        let rotating = AppLog(url: root.appendingPathComponent("rotate.log"), maxBytes: 120)
        for i in 0..<8 { try rotating.write(["event": "test", "payload": String(repeating: "x", count: 100), "i": i], secret: "") }
        try SmokeTests.check(FileManager.default.fileExists(atPath: rotating.url.path + ".3") && !FileManager.default.fileExists(atPath: rotating.url.path + ".4"), "bounded log rotation")
        let mode = try FileManager.default.attributesOfItem(atPath: logURL.path)[.posixPermissions] as? NSNumber
        try SmokeTests.check(mode?.intValue == 0o600, "private log permissions")
    }
}
