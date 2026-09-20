import Foundation

/// JSON lines; each attempt has a request and a response (or transport error).
final class AppLog {
    let url: URL
    let maxBytes: Int
    private static let lock = NSLock()
    init(url: URL, maxBytes: Int = 50 * 1024 * 1024) { self.url = url; self.maxBytes = maxBytes }
    func write(_ event: [String: Any], secret: String) throws {
        Self.lock.lock(); defer { Self.lock.unlock() }
        func redact(_ value: Any) -> Any {
            if let text = value as? String { return secret.isEmpty ? text : text.replacingOccurrences(of: secret, with: "[REDACTED]") }
            if let array = value as? [Any] { return array.map(redact) }
            if let object = value as? [String: Any] { return object.mapValues(redact) }
            return value
        }
        var entry = event
        entry["timestamp"] = ISO8601DateFormatter().string(from: Date())
        var data = try JSONSerialization.data(withJSONObject: redact(entry), options: [.sortedKeys, .fragmentsAllowed])
        data.append(10)
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        if size > 0 && size + data.count > maxBytes {
            let oldest = URL(fileURLWithPath: url.path + ".3")
            if fm.fileExists(atPath: oldest.path) { try fm.removeItem(at: oldest) }
            for index in (1...2).reversed() {
                let source = URL(fileURLWithPath: url.path + ".\(index)")
                if fm.fileExists(atPath: source.path) { try fm.moveItem(at: source, to: URL(fileURLWithPath: url.path + ".\(index + 1)")) }
            }
            try fm.moveItem(at: url, to: URL(fileURLWithPath: url.path + ".1"))
        }
        if !fm.fileExists(atPath: url.path) {
            guard fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw FishError.message("无法创建 app.log。") }
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd(); try handle.write(contentsOf: data)
    }
}
