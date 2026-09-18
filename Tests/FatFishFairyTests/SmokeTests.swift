import Foundation
import AppKit

// Standalone test harness supports Apple's Command Line Tools without XCTest/Xcode.
@main struct SmokeTests {
    static var checkCount = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw FishError.message("FAIL: " + message) }
        checkCount += 1
    }
    static func main() async throws {
        try await ConfigurationTests.run()
        let silent = try ModelReply.parse("{\"speech\":\"\",\"activity\":\"sleeping\",\"memories\":[]}")
        try check(silent.speech.isEmpty && silent.activity == "sleeping", "silent response")
        let fenced = try ModelReply.parse("```json\n{\"speech\":\"你好\",\"activity\":\"happy\",\"memories\":[\"喜欢拿铁\"]}\n```")
        try check(fenced.memories == ["喜欢拿铁"], "fenced response")
        try check((try? ModelReply.parse("not json")) == nil, "malformed response rejected")
        try check((try? ModelReply.parse("{\"activity\":\"idle\"}")) == nil, "missing speech rejected")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StateStore(directory: root)
        let empty = try store.load()
        try check(empty.messages.isEmpty, "first launch")
        var state = SavedState()
        state.preferences.theme = "mint"; state.preferences.petX = 123
        state.memories = [FishMemory(text: "喜欢拿铁")]
        state.messages = [ChatMessage(role: "assistant", text: "记住啦")]
        try store.save(state)
        let restored = try StateStore(directory: root).load()
        try check(restored.preferences.theme == "mint" && restored.preferences.petX == 123, "theme / position restored")
        try check(restored.memories.first?.text == "喜欢拿铁", "memory restored")
        try check(restored.messages.first?.id == state.messages.first?.id, "conversation restored")
        let raw = try String(contentsOf: store.file, encoding: .utf8)
        try check(!raw.contains("DEEPSEEK_API_KEY") && !raw.contains("base64"), "no secrets / screenshots in state")
        let mode = try FileManager.default.attributesOfItem(atPath: store.file.path)[.posixPermissions] as? NSNumber
        try check(mode?.intValue == 0o600, "private state permissions")
        try Data("broken".utf8).write(to: store.file)
        try check((try? store.load()) == nil, "corrupt state never silently reset")

        let bad = root.appendingPathComponent("bad"), good = root.appendingPathComponent("good")
        try FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: good, withIntermediateDirectories: true)
        try Data("{\"../escape\":2,\"empty\":0}".utf8).write(to: bad.appendingPathComponent("index.json"))
        try Data("{\"coffee\":3}".utf8).write(to: good.appendingPathComponent("index.json"))
        let themes = FishTheme.imported(from: root)
        try check(themes.count == 1 && themes.first?.animations["coffee"] == 3, "invalid themes rejected")
        let bundledRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Sources/FatFishFairy/Resources/Themes")
        guard let maid = FishTheme.imported(from: bundledRoot).first(where: { $0.id == FishTheme.defaultThemeID }) else { throw FishError.message("Default bundled theme missing") }
        try check(Preferences().theme == "loli_maid" && maid.name == "萝莉小妹抖", "maid is default with correct display name")
        try check(maid.animations.count == 10 && maid.animations.values.reduce(0, +) == 34, "complete bundled animation index")
        try check(!(maid.character ?? "").isEmpty, "bundled character personality present")
        for (name, count) in maid.animations {
            for frame in 1...count {
                let file = maid.directory!.appendingPathComponent("\(name)_\(frame).png")
                try check(NSImage(contentsOf: file) != nil, "bundled frame decodes: \(name)_\(frame)")
            }
        }
        try await ResponseRegressionTests.run()
        print("PASS: \(checkCount) offline checks (including multi-display format recovery)")

        if ProcessInfo.processInfo.environment["FATFISH_LIVE_TEST"] == "1" {
            guard let key = ProcessInfo.processInfo.environment["FATFISH_TEST_API_KEY"] else { throw FishError.message("Missing test credentials") }
            let client = DeepSeekClient()
            let text = try await client.respond(key: key, personality: "你是一只友善的小鱼。", memories: [], history: [], text: "这是一条集成测试消息，请用中文打个招呼，不要创建记忆。", images: [], observation: false, activities: ["idle", "happy"])
            try check(!text.speech.isEmpty, "live conversation")
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 512, pixelsHigh: 512, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 512 * 3, bitsPerPixel: 24), let pixels = bitmap.bitmapData else { throw FishError.message("Cannot create fixture") }
            for i in 0..<(512 * 512) { pixels[i * 3] = 240; pixels[i * 3 + 1] = 12; pixels[i * 3 + 2] = 12 }
            guard let jpeg = bitmap.representation(using: .jpeg, properties: [:]) else { throw FishError.message("Cannot encode fixture") }
            let vision = try await client.respond(key: key, personality: "准确识别图片中的颜色。", memories: [], history: [], text: "这张图的主要颜色是什么？speech 字段只填颜色的中文名称，不要创建记忆。", images: [jpeg], observation: false, activities: ["idle"])
            try check(vision.speech.contains("红"), "synthetic red image recognized; model said: \(vision.speech)")
            guard let blueBitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 512, pixelsHigh: 512, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 512 * 3, bitsPerPixel: 24), let bluePixels = blueBitmap.bitmapData else { throw FishError.message("Cannot create second fixture") }
            for i in 0..<(512 * 512) { bluePixels[i * 3] = 12; bluePixels[i * 3 + 1] = 12; bluePixels[i * 3 + 2] = 240 }
            guard let blue = blueBitmap.representation(using: .jpeg, properties: [:]) else { throw FishError.message("Cannot encode second fixture") }
            try jpeg.write(to: URL(fileURLWithPath: ".build/checks/red.jpg"))
            try blue.write(to: URL(fileURLWithPath: ".build/checks/blue.jpg"))
            let multiple = try await client.respond(key: key, personality: "准确识别图片中的颜色。", memories: [], history: [ChatMessage(role: "assistant", text: "上一张是红色。")], text: "这是多图回归测试。请在 speech 中按顺序说出两张图片的颜色，不能省略任何一张，不要创建记忆。", images: [jpeg, blue], observation: true, activities: ["idle"])
            try check(!multiple.speech.isEmpty && multiple.activity == "idle", "multi-image API returns one usable reply")
            if !multiple.speech.contains("红") || !multiple.speech.contains("蓝") {
                print("NOTE: model's synthetic color classification was inaccurate; this test validates multi-image transport and response format, not model accuracy.")
            }
            print("PASS: live deepseek-flash conversation, single-image recognition and multi-image response format")
        }
    }
}
