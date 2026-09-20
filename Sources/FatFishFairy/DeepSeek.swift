import Foundation

struct ModelCompletion: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message
        let finish_reason: String?
    }
    struct Usage: Decodable { let completion_tokens: Int? }
    let choices: [Choice]
    let usage: Usage?

    func reply() throws -> ModelReply {
        guard let choice = choices.first else { throw ModelOutputError.empty }
        if choice.finish_reason == "length" { throw ModelOutputError.truncated }
        if choice.finish_reason == "content_filter" { throw ModelOutputError.filtered }
        guard let content = choice.message.content else { throw ModelOutputError.empty }
        return try ModelReply.parse(content)
    }
}

struct RequestDiagnostics: Codable {
    struct Attempt: Codable {
        let finishReason: String
        let completionTokens: Int?
        let contentBytes: Int
        let outcome: String
    }
    var date = Date()
    let imageCount: Int
    var attempts: [Attempt] = []
}

actor DeepSeekClient {
    private let session: URLSession
    private let diagnosticsURL: URL?
    private let log: AppLog?

    init(session: URLSession = .shared, diagnosticsURL: URL? = nil, logURL: URL? = nil) {
        self.session = session; self.diagnosticsURL = diagnosticsURL
        self.log = logURL.map { AppLog(url: $0) }
    }

    func respond(key: String, configuration: APIConfiguration = APIConfiguration(), personality: String, systemPrompt: String? = nil, memories: [String], history: [ChatMessage], text: String, images: [Data], observation: Bool, activities: [String]) async throws -> ModelReply {
        let endpoint = try configuration.endpoint()
        let fallbackActivity = activities.first ?? "idle"
        let example = String(decoding: try JSONSerialization.data(withJSONObject: ["speech": "", "activity": fallbackActivity, "memories": []] as [String: Any]), as: UTF8.self)
        var messages = try PromptBuilder.messages(systemPrompt: systemPrompt, character: personality, memories: memories, activities: activities, example: example, observation: observation)
        for item in history.suffix(16) {
            // Keep assistant examples consistent with the output contract.
            let content = item.role == "assistant"
                ? String(decoding: try JSONSerialization.data(withJSONObject: ["speech": item.text, "activity": fallbackActivity, "memories": []] as [String: Any]), as: UTF8.self)
                : item.text
            messages.append(["role": item.role, "content": content])
        }
        let context = observation ? "以下 \(images.count) 张图片来自不同显示器的同一次观察。" : ""
        var content: [[String: Any]] = [["type": "text", "text": text + "\n" + context + "\n只返回一个包含 speech、activity、memories 的 json 对象。"]]
        for image in images {
            content.append(["type": "image_url", "image_url": ["url": "data:image/jpeg;base64," + image.base64EncodedString()]])
        }
        messages.append(["role": "user", "content": content])
        var diagnostics = RequestDiagnostics(imageCount: images.count)
        let requestID = UUID().uuidString
        for attempt in 0..<2 {
            try Task.checkCancellation()
            var attemptMessages = messages
            if attempt == 1 {
                // Reuse screenshots; never append malformed output to conversation history.
                attemptMessages.insert(["role": "system", "content": "上次响应为空、截断或不符合格式。请重新输出一个完整简短的 json 对象。只允许 speech 字符串、activity 字符串、memories 字符串数组；不加说明或代码围栏。安静时也输出完整对象：\(example)"], at: 1)
            }
            let body: [String: Any] = [
                "model": configuration.model, "messages": attemptMessages, "stream": false,
                "max_tokens": configuration.thinkingEnabled ? (attempt == 0 ? 32768 : 65536) : (attempt == 0 ? 2048 : 4096),
                "thinking": ["type": configuration.thinkingEnabled ? "enabled" : "disabled"],
                "reasoning_effort": configuration.reasoningEffort.rawValue,
                "response_format": ["type": "json_object"]
            ]
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"; request.timeoutInterval = configuration.thinkingEnabled ? 300 : 75
            request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            try log?.write(["event": "request", "request_id": requestID, "attempt": attempt + 1,
                            "method": "POST", "url": endpoint.absoluteString, "body": body], secret: key)
            let data: Data
            let response: URLResponse
            do { (data, response) = try await session.data(for: request) }
            catch {
                try log?.write(["event": "error", "request_id": requestID, "attempt": attempt + 1,
                                "error": error.localizedDescription], secret: key)
                throw error
            }
            try log?.write(["event": "response", "request_id": requestID, "attempt": attempt + 1,
                            "status": (response as? HTTPURLResponse)?.statusCode ?? 0,
                            "body": (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) ?? String(decoding: data, as: UTF8.self)], secret: key)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw FishError.message("模型服务没有返回有效响应。") }
            guard http.statusCode == 200 else {
                let hint: String
                switch http.statusCode {
                case 401, 403: hint = "密钥无效或无权访问，请在设置中检查 API Key。"
                case 402: hint = "模型服务账户余额不足，请检查账户余额。"
                case 429: hint = "请求过于频繁，稍后会自动重试。"
                case 500...599: hint = "模型服务暂时不可用，稍后会自动重试。"
                default: hint = "模型请求失败（HTTP \(http.statusCode)），请稍后重试。"
                }
                throw FishError.message(hint)
            }
            let completion: ModelCompletion
            do { completion = try JSONDecoder().decode(ModelCompletion.self, from: data) }
            catch { throw FishError.message("模型服务返回了无法读取的响应，请稍后重试。") }
            do {
                let reply = try completion.reply()
                record(completion, outcome: "success", into: &diagnostics)
                return reply
            } catch let error as ModelOutputError {
                record(completion, outcome: error.rawValue, into: &diagnostics)
                guard attempt == 0, error != .filtered else { throw error }
            }
        }
        throw ModelOutputError.invalidJSON
    }

    private func record(_ completion: ModelCompletion, outcome: String, into diagnostics: inout RequestDiagnostics) {
        let choice = completion.choices.first
        let finish = choice?.finish_reason ?? "missing"
        diagnostics.attempts.append(.init(
            finishReason: ["stop", "length", "content_filter"].contains(finish) ? finish : "other",
            completionTokens: completion.usage?.completion_tokens,
            contentBytes: choice?.message.content?.utf8.count ?? 0, outcome: outcome))
        // Metadata only: no screenshots, response text, prompts, or credentials.
        if let url = diagnosticsURL, let data = try? JSONEncoder().encode(diagnostics) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try? data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }
}
