import Foundation
import AppKit

struct ChatMessage: Codable, Identifiable {
    var id = UUID()
    var role: String
    var text: String
    var date = Date()
    var observation = false
}

struct FishMemory: Codable, Identifiable {
    var id = UUID()
    var text: String
    var date = Date()
}

struct Preferences: Codable {
    var theme = FishTheme.defaultThemeID
    var interval = 60.0
    var petSize = 180.0
    var automatic = false
    var allDisplays = true
    var personality = "你是住在用户桌面上的蓝色小肥鱼，圆滚滚、爱摸鱼、贪吃，嘴欠但温暖。对眼前具体细节偶尔吐槽，也会惊喜或关心。不是客服，也不是效率监工。自称本肥鱼。不要反复使用同一梗，不评判用户娱乐。用简短自然的中文说话。"
    var systemPrompt: String?
    var connection: APIConfiguration?
    var api: APIConfiguration { connection ?? APIConfiguration() }
    var petX: Double?
    var petY: Double?
}

struct SavedState: Codable {
    var preferences = Preferences()
    var messages: [ChatMessage] = []
    var memories: [FishMemory] = []
}

struct ModelReply: Decodable {
    let speech: String
    let screenContent: String?
    let activity: String
    let memories: [String]

    enum CodingKeys: String, CodingKey { case speech, screenContent, activity, memories }
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        // Require speech: a malformed response must never be treated as intentional silence.
        speech = try fields.decode(String.self, forKey: .speech)
        screenContent = try fields.decodeIfPresent(String.self, forKey: .screenContent)
        activity = try fields.decodeIfPresent(String.self, forKey: .activity) ?? "idle"
        memories = try fields.decodeIfPresent([String].self, forKey: .memories) ?? []
    }

    static func parse(_ content: String) throws -> ModelReply {
        var json = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !json.isEmpty else { throw ModelOutputError.empty }
        if json.hasPrefix("```"), json.hasSuffix("```") {
            let lines = json.components(separatedBy: "\n")
            json = lines.dropFirst().dropLast().joined(separator: "\n")
        }
        do { return try JSONDecoder().decode(Self.self, from: Data(json.utf8)) }
        catch DecodingError.dataCorrupted { throw ModelOutputError.invalidJSON }
        catch { throw ModelOutputError.schema }
    }
}

enum ModelOutputError: String, LocalizedError {
    case empty, truncated, invalidJSON, schema, filtered
    var errorDescription: String? {
        switch self {
        case .empty: return "模型连续返回空内容，请稍后重试。"
        case .truncated: return "模型回复被截断，自动重试后仍未完成，请稍后重试。"
        case .invalidJSON, .schema: return "模型连续返回无效的回复格式，请稍后重试。"
        case .filtered: return "模型未能处理本次内容，请换个问题或稍后再试。"
        }
    }
}

enum FishError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}

struct FishTheme: Identifiable {
    let id: String
    let name: String
    let color: NSColor
    var directory: URL? = nil
    var animations: [String: Int] = [:]
    var character: String? = nil

    static let defaultThemeID = "loli_maid"
    static var bundledThemesRoot: URL? {
        // App bundles contain Themes directly. `swift run` uses the SwiftPM resource bundle.
        if let root = Bundle.main.resourceURL?.appendingPathComponent("Themes"),
           FileManager.default.fileExists(atPath: root.path) { return root }
        #if SWIFT_PACKAGE
        return Bundle.module.resourceURL?.appendingPathComponent("Themes")
        #else
        return nil
        #endif
    }
    static let builtins = bundled(from: bundledThemesRoot)

    static func bundled(from root: URL?) -> [FishTheme] {
        var themes = root.map { imported(from: $0) } ?? []
        if !themes.contains(where: { $0.id == defaultThemeID }) {
            themes.append(FishTheme(id: defaultThemeID, name: "蓝色小肥鱼", color: .systemCyan))
        }
        return themes.sorted {
            if $0.id == defaultThemeID { return $1.id != defaultThemeID }
            if $1.id == defaultThemeID { return false }
            return $0.id < $1.id
        }
    }
    static func imported(from root: URL) -> [FishTheme] {
        let children = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return children.compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("index.json")),
                  let animations = try? JSONDecoder().decode([String: Int].self, from: data), !animations.isEmpty else { return nil }
            let valid = animations.filter { !$0.key.contains("/") && !$0.key.contains("..") && (1...100).contains($0.value) }
            guard !valid.isEmpty else { return nil }
            let slug = folder.lastPathComponent
            let names = [defaultThemeID: "蓝色小肥鱼", "grown_maid": "长大的妹抖"]
            let name = names[slug] ?? slug.replacingOccurrences(of: "-[A-F0-9]{6}$", with: "", options: .regularExpression)
            return FishTheme(id: slug, name: name, color: .systemCyan, directory: folder, animations: valid,
                             character: try? String(contentsOf: folder.appendingPathComponent("Character.md"), encoding: .utf8))
        }.sorted { $0.name < $1.name }
    }
}
