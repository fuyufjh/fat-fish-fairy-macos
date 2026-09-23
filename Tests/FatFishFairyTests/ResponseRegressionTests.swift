import Foundation

final class StubProtocol: URLProtocol {
    static var transportError: Error?
    static var responses: [(Int, Data)] = []
    static var bodies: [[String: Any]] = []
    static var urls: [String] = []
    static var authorizations: [String] = []
    static let lock = NSLock()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count <= 0 { break }
                data.append(contentsOf: bytes.prefix(count))
            }
        }
        Self.lock.lock()
        Self.urls.append(request.url!.absoluteString)
        Self.authorizations.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
        Self.bodies.append((try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:])
        let response = Self.responses.isEmpty ? (500, Data()) : Self.responses.removeFirst()
        let transportError = Self.transportError; Self.transportError = nil
        Self.lock.unlock()
        if let transportError { client?.urlProtocol(self, didFailWithError: transportError); return }
        let http = HTTPURLResponse(url: request.url!, statusCode: response.0, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.1)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
    static func reset(_ responses: [(Int, Data)]) {
        lock.lock(); defer { lock.unlock() }
        Self.responses = responses; transportError = nil; bodies = []; urls = []; authorizations = []
    }
}

struct ResponseRegressionTests {
    static func completion(_ text: String?, finish: String = "stop") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": text as Any? ?? NSNull()], "finish_reason": finish]], "usage": ["completion_tokens": 30]])
    }
    static func checkDayBoundaries() throws {
        let cases = [
            ("Asia/Shanghai", "2026-09-22T19:59:59Z", "2026-09-22"),
            ("Asia/Shanghai", "2026-09-22T20:00:00Z", "2026-09-23"),
            ("Asia/Shanghai", "2026-09-22T16:00:00Z", "2026-09-22"),
            ("Asia/Shanghai", "2026-12-31T19:59:59Z", "2026-12-31"),
            ("Asia/Shanghai", "2026-12-31T20:00:00Z", "2027-01-01"),
            ("America/New_York", "2026-03-08T07:59:59Z", "2026-03-07"),
            ("America/New_York", "2026-03-08T08:00:00Z", "2026-03-08"),
            ("America/New_York", "2026-11-01T08:59:59Z", "2026-10-31"),
            ("America/New_York", "2026-11-01T09:00:00Z", "2026-11-01"),
            ("America/New_York", "2026-09-22T20:00:00Z", "2026-09-22")
        ]
        for (zone, timestamp, expected) in cases {
            let date = ISO8601DateFormatter().date(from: timestamp)!
            try SmokeTests.check(DailyMemo.day(for: date, timeZone: TimeZone(identifier: zone)!) == expected, "local 4am workday: " + timestamp + " " + zone)
        }
    }
    static func run() async throws {
        try SmokeTests.check(Preferences().allDisplays, "all displays on by default")
        var preferences = Preferences(); preferences.allDisplays = false
        let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        try SmokeTests.check(!restored.allDisplays, "explicit main-display-only choice survives")
        let partial = try ModelReply.parse("{\"speech\":\"你好\"}")
        try SmokeTests.check(partial.activity == "idle" && partial.memories.isEmpty, "optional metadata defaults")
        try SmokeTests.check((try? ModelReply.parse("{}")) == nil, "missing speech cannot become silence")
        try SmokeTests.check((try? ModelReply.parse("{\"speech\":null}")) == nil, "null speech rejected")
        try SmokeTests.check((try? ModelReply.parse("[{\"speech\":\"one\"},{\"speech\":\"two\"}]")) == nil, "per-display array requires retry")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let diagnostics = directory.appendingPathComponent("request.json")
        let client = DeepSeekClient(session: session, diagnosticsURL: diagnostics)
        let valid = "{\"memo\":\"10:30 调试代码\",\"screenContent\":\"用户正在调试代码\",\"speech\":\"ok\",\"activity\":\"idle\",\"memories\":[]}"
        var fixtures: [(String?, String)] = [(nil,"stop"), ("  ","stop"), ("{\"speech\":\"unfinished", "length"), ("[]", "stop"), ("{\"speech\":17}", "stop"), ("{\"speech\":\"old format\"}", "stop"), ("{\"speech\":\"\",\"screenContent\":\"  \"}", "stop")]
        for memo in [NSNull(), "", "  ", 17, String(repeating: "字", count: 1001)] as [Any] {
            let invalid = try JSONSerialization.data(withJSONObject: ["speech": "", "screenContent": "编辑代码", "memo": memo])
            fixtures.append((String(decoding: invalid, as: UTF8.self), "stop"))
        }
        fixtures.append(("{\"speech\":\"\",\"screenContent\":\"编辑代码\"}", "stop"))
        for (text, finish) in fixtures {
            StubProtocol.reset([(200, try completion(text, finish: finish)), (200, try completion(valid))])
            let result = try await client.respond(key: "test-only-key", personality: "test", memories: [], history: [ChatMessage(role: "assistant", text: "earlier reply")], text: "test", images: [Data([1]), Data([2])], observation: true, activities: ["idle"], memo: "10:00 retry-memo-marker")
            try SmokeTests.check(result.speech == "ok" && StubProtocol.bodies.count == 2, "format failure retried exactly once")
            let first = StubProtocol.bodies[0], second = StubProtocol.bodies[1]
            try SmokeTests.check(first["max_tokens"] as? Int == 2048 && second["max_tokens"] as? Int == 4096, "retry increases output budget")
            let firstMessages = first["messages"] as! [[String: Any]], secondMessages = second["messages"] as! [[String: Any]]
            let originalContext = try JSONSerialization.data(withJSONObject: firstMessages, options: .sortedKeys)
            let retryContext = try JSONSerialization.data(withJSONObject: secondMessages.enumerated().filter { $0.offset != 1 }.map { $0.element }, options: .sortedKeys)
            try SmokeTests.check(originalContext == retryContext, "retry preserves original memo, time and all context")
            let a = try JSONSerialization.data(withJSONObject: firstMessages.last!, options: .sortedKeys)
            let b = try JSONSerialization.data(withJSONObject: secondMessages.last!, options: .sortedKeys)
            try SmokeTests.check(a == b, "same multi-display images reused for retry")
            let blocks = firstMessages.last!["content"] as! [[String: Any]]
            try SmokeTests.check(blocks.filter { $0["type"] as? String == "image_url" }.count == 2, "both displays retained")
            let payload = String(decoding: try JSONSerialization.data(withJSONObject: firstMessages), as: UTF8.self)
            try SmokeTests.check(!payload.contains("earlier reply") && !firstMessages.contains { $0["role"] as? String == "assistant" }, "observation excludes speech history on retry")
            let report = try JSONDecoder().decode(RequestDiagnostics.self, from: Data(contentsOf: diagnostics))
            try SmokeTests.check(report.imageCount == 2 && report.attempts.count == 2 && report.attempts.last?.outcome == "success", "sanitized diagnostics include recovery")
            let raw = try String(contentsOf: diagnostics, encoding: .utf8)
            try SmokeTests.check(!raw.contains("test-only-key") && !raw.contains("earlier reply") && !raw.contains("base64"), "diagnostics exclude private payload")
        }
        let store = StateStore(directory: directory.appendingPathComponent("state"))
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        let date = ISO8601DateFormatter().date(from: "2026-09-23T07:50:00Z")!
        let day = DailyMemo.day(for: date, timeZone: zone)
        let initial = try store.dailyMemo(for: day)
        try SmokeTests.check(initial == "开始了新的一天", "new day starts with initial memo")
        let oldMemo = "10:30-15:40 review MR：修复登录\n10:50-15:40 写文档：接口说明"
        let newMemo = "10:30-15:50 review MR：修复登录\n10:50-15:50 写文档：接口说明"
        try store.saveDailyMemo(oldMemo, for: day)
        let restoredMemo = try StateStore(directory: store.directory).dailyMemo(for: day)
        try SmokeTests.check(restoredMemo == oldMemo, "daily memo survives restart")
        let silent = String(decoding: try JSONSerialization.data(withJSONObject: ["screenContent": "用户正在阅读文档", "speech": "", "memo": newMemo]), as: UTF8.self)
        StubProtocol.reset([(200, try completion(silent))])
        let result = try await client.respond(key: "test", personality: "test", systemPrompt: "legacy-custom-prompt", memories: ["memory-marker"], history: [ChatMessage(role: "user", text: "chat-marker"), ChatMessage(role: "assistant", text: "speech-marker", observation: true)], text: "test", images: [Data([1])], observation: true, activities: ["idle"], memo: restoredMemo, date: date, timeZone: zone)
        try SmokeTests.check(result.speech.isEmpty && result.screenContent == "用户正在阅读文档" && result.memo == newMemo, "silent observation still produces summary and full memo")
        let payload = String(decoding: try JSONSerialization.data(withJSONObject: StubProtocol.bodies[0]), as: UTF8.self)
        try SmokeTests.check(payload.contains("15:40") && payload.contains("2026-09-23 15:50:00") && payload.contains("Asia") && payload.contains("Shanghai"), "request includes memo and local observation time")
        try SmokeTests.check(!payload.contains("speech-marker") && !payload.contains("chat-marker") && !payload.contains("memory-marker"), "observation excludes previous speech, chat and memories")
        try SmokeTests.check(payload.contains("screenContent") && payload.contains("legacy-custom-prompt") && payload.contains("1000"), "new observation contract applies with custom prompts")
        try store.saveDailyMemo(result.memo!, for: day)
        let afterSilence = try StateStore(directory: store.directory).dailyMemo(for: day)
        try SmokeTests.check(afterSilence == newMemo && !afterSilence.contains("15:40"), "silent observation replaces memo instead of appending")
        let nextDay = "2026-09-24"
        let nextMemo = try store.dailyMemo(for: nextDay)
        try SmokeTests.check(nextMemo == DailyMemo.initial, "new day does not inherit previous memo")
        try store.saveDailyMemo("04:00 阅读邮件", for: nextDay)
        try store.saveDailyMemo("23:59 阅读文档", for: day)
        let currentMemo = try store.dailyMemo(for: nextDay)
        try SmokeTests.check(currentMemo == "04:00 阅读邮件", "late previous-day response cannot overwrite new day")
        for invalid in ["", " \n ", String(repeating: "字", count: 1001)] {
            do {
                try store.saveDailyMemo(invalid, for: nextDay)
                throw FishError.message("FAIL: invalid memo should not persist")
            } catch ModelOutputError.schema {}
        }
        let unchanged = try store.dailyMemo(for: nextDay)
        try SmokeTests.check(unchanged == currentMemo, "invalid memo preserves saved record")
        let limitMemo = String(repeating: "字", count: 1000)
        try store.saveDailyMemo(limitMemo, for: nextDay)
        try SmokeTests.check(DailyMemo.isValid(limitMemo), "1000 Unicode characters accepted")
        StubProtocol.reset([(200, try completion("{\"speech\":\"hello\"}"))])
        _ = try await client.respond(key: "test", personality: "test", memories: [], history: [ChatMessage(role: "assistant", text: "manual-reply"), ChatMessage(role: "assistant", text: "observation-speech", observation: true)], text: "test", images: [], observation: false, activities: ["idle"], memo: "private-memo-marker")
        let chatPayload = String(decoding: try JSONSerialization.data(withJSONObject: StubProtocol.bodies[0]), as: UTF8.self)
        try SmokeTests.check(chatPayload.contains("manual-reply") && !chatPayload.contains("observation-speech") && !chatPayload.contains("private-memo-marker"), "manual chat keeps its own history without observation context")
        try checkDayBoundaries()
        StubProtocol.reset([(200, try completion("{}")), (200, try completion("{}"))])
        do {
            _ = try await client.respond(key: "test", personality: "test", memories: [], history: [], text: "test", images: [], observation: false, activities: ["idle"])
            throw FishError.message("FAIL: exhausted retry should throw")
        } catch let error as ModelOutputError {
            try SmokeTests.check(error == .schema && StubProtocol.bodies.count == 2, "retry bounded with accurate failure")
        }
        StubProtocol.reset([(401, Data())])
        do {
            _ = try await client.respond(key: "test", personality: "test", memories: [], history: [], text: "test", images: [], observation: false, activities: ["idle"])
            throw FishError.message("FAIL: unauthorized should throw")
        } catch let error as FishError {
            try SmokeTests.check(error.localizedDescription.contains("密钥") && StubProtocol.bodies.count == 1, "auth failures do not retry")
        }
        StubProtocol.reset([(200, try completion("", finish: "content_filter"))])
        do {
            _ = try await client.respond(key: "test", personality: "test", memories: [], history: [], text: "test", images: [], observation: false, activities: ["idle"])
            throw FishError.message("FAIL: filtered should throw")
        } catch let error as ModelOutputError {
            try SmokeTests.check(error == .filtered && StubProtocol.bodies.count == 1, "filtered content does not retry")
        }
    }
}
