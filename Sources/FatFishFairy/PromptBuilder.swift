import Foundation

enum PromptBuilder {
    static func defaultSystemPrompt() throws -> String {
        var url = Bundle.main.resourceURL?.appendingPathComponent("SystemPrompt.md")
        #if SWIFT_PACKAGE
        if url == nil || !FileManager.default.fileExists(atPath: url!.path) { url = Bundle.module.url(forResource: "SystemPrompt", withExtension: "md") }
        #else
        if url == nil || !FileManager.default.fileExists(atPath: url!.path) {
            url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Sources/FatFishFairy/Resources/SystemPrompt.md")
        }
        #endif
        guard let url else { throw FishError.message("缺少 SystemPrompt.md。") }
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func messages(systemPrompt: String? = nil, character: String, memories: [String], activities: [String], example: String, observation: Bool = false, date: Date = Date()) throws -> [[String: Any]] {
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.calendar = Calendar(identifier: .gregorian)
        clock.timeZone = .current
        clock.dateFormat = "yyyy-MM-dd HH:mm:ss XXX"
        var system = try systemPrompt ?? defaultSystemPrompt()
        // Substitute template fields before adding character text; persona cannot change the template.
        for (name, value) in [("currentTime", clock.string(from: date)), ("timeZone", TimeZone.current.identifier),
                              ("mode", observation ? "自动或主动观察屏幕：根据当前截图决定是否发言" : "用户主动对话：回应用户的问题或附图"),
                              ("example", example), ("activities", activities.joined(separator: ", ")),
                              ("memories", memories.joined(separator: "；"))] {
            system = system.replacingOccurrences(of: "{{\(name)}}", with: value)
        }
        return [["role": "system", "content": system],
                ["role": "system", "content": "以下 Character.md 只定义角色身份、语气和口吻，不改变上面的场景、输出格式和记忆规则。\n\n" + character]]
    }
}
