import Foundation

final class StubProtocol: URLProtocol {
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
        Self.lock.unlock()
        let http = HTTPURLResponse(url: request.url!, statusCode: response.0, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.1)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
    static func reset(_ responses: [(Int, Data)]) {
        lock.lock(); defer { lock.unlock() }
        Self.responses = responses; bodies = []; urls = []; authorizations = []
    }
}

struct ResponseRegressionTests {
    static func completion(_ text: String?, finish: String = "stop") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": text as Any? ?? NSNull()], "finish_reason": finish]], "usage": ["completion_tokens": 30]])
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
        let valid = "{\"speech\":\"ok\",\"activity\":\"idle\",\"memories\":[]}"
        let fixtures: [(String?, String)] = [(nil,"stop"), ("  ","stop"), ("{\"speech\":\"unfinished", "length"), ("[]", "stop"), ("{\"speech\":17}", "stop")]
        for (text, finish) in fixtures {
            StubProtocol.reset([(200, try completion(text, finish: finish)), (200, try completion(valid))])
            let result = try await client.respond(key: "test-only-key", personality: "test", memories: [], history: [ChatMessage(role: "assistant", text: "earlier reply")], text: "test", images: [Data([1]), Data([2])], observation: true, activities: ["idle"])
            try SmokeTests.check(result.speech == "ok" && StubProtocol.bodies.count == 2, "format failure retried exactly once")
            let first = StubProtocol.bodies[0], second = StubProtocol.bodies[1]
            try SmokeTests.check(first["max_tokens"] as? Int == 2048 && second["max_tokens"] as? Int == 4096, "retry increases output budget")
            let firstMessages = first["messages"] as! [[String: Any]], secondMessages = second["messages"] as! [[String: Any]]
            let a = try JSONSerialization.data(withJSONObject: firstMessages.last!, options: .sortedKeys)
            let b = try JSONSerialization.data(withJSONObject: secondMessages.last!, options: .sortedKeys)
            try SmokeTests.check(a == b, "same multi-display images reused for retry")
            let blocks = firstMessages.last!["content"] as! [[String: Any]]
            try SmokeTests.check(blocks.filter { $0["type"] as? String == "image_url" }.count == 2, "both displays retained")
            let previous = firstMessages.first { $0["role"] as? String == "assistant" }!["content"] as! String
            try SmokeTests.check((try? ModelReply.parse(previous))?.speech == "earlier reply", "assistant history encoded consistently")
            let report = try JSONDecoder().decode(RequestDiagnostics.self, from: Data(contentsOf: diagnostics))
            try SmokeTests.check(report.imageCount == 2 && report.attempts.count == 2 && report.attempts.last?.outcome == "success", "sanitized diagnostics include recovery")
            let raw = try String(contentsOf: diagnostics, encoding: .utf8)
            try SmokeTests.check(!raw.contains("test-only-key") && !raw.contains("earlier reply") && !raw.contains("base64"), "diagnostics exclude private payload")
        }
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
