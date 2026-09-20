import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor final class FishModel: ObservableObject {
    @Published var preferences: Preferences
    @Published var messages: [ChatMessage]
    @Published var memories: [FishMemory]
    @Published var themes = FishTheme.builtins
    @Published var hasOlderMessages = false
    @Published var historyRevision = UUID()
    @Published var status = "准备好陪你摸鱼了"
    @Published var bubble = "本肥鱼已就位。\n双击我，聊两句？"
    @Published var activity = "idle"
    @Published var busy = false
    var hasKey: Bool { !preferences.api.apiKey.isEmpty }
    @Published var screenPermission = ScreenCapture.hasPermission
    @Published var error: String?
    @Published var draft = ""
    @Published var attachment: Data?
    @Published var attachmentName: String?
    @Published var lastObservation: Date?
    @Published var failures = 0
    @Published var petVisible = true
    @Published var sessionActive = true
    let store = StateStore()
    private let client = DeepSeekClient(diagnosticsURL: StateStore().directory.appendingPathComponent("last-request.json"), logURL: StateStore().directory.appendingPathComponent("app.log"))
    private var requestTask: Task<Void, Never>?
    private var timer: Timer?
    private var bubbleTask: Task<Void, Never>?
    private var nextObservation = Date.distantFuture
    private var generation = UUID()
    private var loadFailed = false

    var theme: FishTheme { themes.first { $0.id == preferences.theme } ?? themes[0] }
    var themeRoot: URL { store.directory.appendingPathComponent("Themes", isDirectory: true) }
    var activities: [String] { theme.directory == nil ? ["idle", "happy", "thinking", "sleeping", "programming", "coffee"] : theme.animations.keys.sorted() }

    init() {
        var state = SavedState()
        var loadError: String?
        do { state = try store.load() }
        catch { loadError = "本地记录读取失败，已保留原文件。请先备份 state.sqlite 和旧版 state.json 后修复数据，再重新启动。" }
        preferences = state.preferences; messages = state.messages; memories = state.memories
        if let loadError { self.error = loadError; loadFailed = true }
        themes += FishTheme.imported(from: themeRoot)
        if !themes.contains(where: { $0.id == preferences.theme }) { preferences.theme = FishTheme.defaultThemeID }
        hasOlderMessages = (try? store.hasMessages(before: messages.first?.id)) ?? false
        do { try AppLog(url: store.directory.appendingPathComponent("app.log")).write(["event": "application_start", "loaded_messages": messages.count], secret: preferences.api.apiKey) }
        catch { if self.error == nil { self.error = "日志初始化失败：\(error.localizedDescription)" } }
        nextObservation = Date().addingTimeInterval(8)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func persist() {
        guard !loadFailed else { return }
        do {
            try store.save(SavedState(preferences: preferences, messages: messages, memories: memories))
            if !(AppDelegate.shared?.mainWindow?.isVisible ?? false) { messages = Array(messages.suffix(50)) }
            hasOlderMessages = try store.hasMessages(before: messages.first?.id)
        }
        catch { self.error = "本地保存失败：\(error.localizedDescription)" }
    }

    func reloadLatestMessages() {
        guard !loadFailed else { return }
        do {
            // Persist unsaved messages before replacing the visible window.
            try store.save(SavedState(preferences: preferences, messages: messages, memories: memories))
            messages = try store.messagePage()
            hasOlderMessages = try store.hasMessages(before: messages.first?.id)
            historyRevision = UUID()
        } catch { self.error = "聊天记录加载失败：\(error.localizedDescription)" }
    }

    func loadOlderMessages() {
        guard !loadFailed, hasOlderMessages, let first = messages.first?.id else { return }
        do {
            messages.insert(contentsOf: try store.messagePage(before: first), at: 0)
            hasOlderMessages = try store.hasMessages(before: messages.first?.id)
        } catch { self.error = "聊天记录加载失败：\(error.localizedDescription)" }
    }

    func chooseTheme(_ id: String) {
        guard preferences.theme != id, themes.contains(where: { $0.id == id }) else { return }
        cancel(); preferences.theme = id; activity = "idle"
        showBubble("换个样子，继续陪你。")
        persist()
    }

    func tick() {
        screenPermission = ScreenCapture.hasPermission
        guard preferences.automatic, !busy, sessionActive, Date() >= nextObservation else { return }
        guard screenPermission else { status = "等待屏幕录制权限"; return }
        guard hasKey else { status = "等待配置 API Key"; return }
        observe()
    }

    func setAutomatic(_ enabled: Bool) {
        preferences.automatic = enabled
        if enabled { nextObservation = Date(); status = "准备观察屏幕" }
        else { cancel(); status = "已暂停观察"; activity = "sleeping" }
        persist()
    }

    func cancel() {
        generation = UUID(); requestTask?.cancel(); requestTask = nil; busy = false
        nextObservation = Date().addingTimeInterval(preferences.interval)
    }

    func sessionChanged(active: Bool) {
        sessionActive = active
        if !active { cancel(); status = "屏幕休息中"; activity = "sleeping" }
        else { nextObservation = Date().addingTimeInterval(3); status = "欢迎回来" }
    }

    func requestPermission() {
        if !CGRequestScreenCaptureAccess() {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
        screenPermission = ScreenCapture.hasPermission
    }

    func observe() {
        guard !busy, sessionActive else { return }
        guard screenPermission else { error = "请先在「设置」中开启屏幕录制权限。"; return }
        run(text: "现在是 \(Date().formatted(date: .abbreviated, time: .shortened))。看看当前屏幕，有值得分享的新发现吗？没有就保持安静。", observation: true, attachment: nil)
    }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !text.isEmpty || attachment != nil else { return }
        guard hasKey else { error = "请在设置中填写并保存 API Key。"; return }
        let image = attachment
        run(text: text.isEmpty ? "看看这张图，告诉我你发现了什么。" : text, observation: false, attachment: image)
        draft = ""; attachment = nil; attachmentName = nil
    }

    private func run(text: String, observation: Bool, attachment: Data?) {
        let key = preferences.api.apiKey
        guard !key.isEmpty else { error = "请先在设置中配置 API Key。"; return }
        error = nil; busy = true; activity = "thinking"
        status = observation ? "V · 正在看屏幕…" : "F · 小肥鱼想一想…"
        let requestID = UUID(); generation = requestID
        let history = messages
        if !observation { messages.append(ChatMessage(role: "user", text: text + (attachment != nil ? "\n[附带图片]" : ""))); persist() }
        let personality = theme.character ?? preferences.personality
        let systemPrompt = preferences.systemPrompt
        let memoryTexts = memories.map(\.text)
        let actions = activities
        let allDisplays = preferences.allDisplays
        let configuration = preferences.api
        requestTask = Task {
            do {
                let images: [Data]
                if observation { images = try await ScreenCapture.capture(allDisplays: allDisplays) }
                else { images = attachment.map { [$0] } ?? [] }
                try Task.checkCancellation()
                guard generation == requestID else { return }
                status = "F · 小肥鱼想一想…"
                let reply = try await client.respond(key: key, configuration: configuration, personality: personality, systemPrompt: systemPrompt, memories: memoryTexts,
                                                     history: history, text: text, images: images, observation: observation, activities: actions)
                try Task.checkCancellation()
                guard generation == requestID else { return }
                failures = 0; busy = false
                if observation { lastObservation = Date() }
                activity = actions.contains(reply.activity) ? reply.activity : actions[0]
                if !reply.speech.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    messages.append(ChatMessage(role: "assistant", text: reply.speech, observation: observation))
                    showBubble(reply.speech)
                    status = "刚刚聊了两句"
                } else { bubble = ""; status = "安静陪你一会儿" }
                // Only explicit conversations may contribute durable memories, never screenshots.
                if !observation {
                    for item in reply.memories.prefix(3) {
                        let clean = String(item.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
                        if !clean.isEmpty, !memories.contains(where: { $0.text == clean }) { memories.append(FishMemory(text: clean)) }
                    }
                    memories = Array(memories.suffix(60))
                }
                persist()
                nextObservation = Date().addingTimeInterval(preferences.interval)
            } catch {
                guard generation == requestID, !Task.isCancelled else { return }
                busy = false; failures += 1; activity = "idle"
                self.error = error.localizedDescription
                status = "L\(failures) · 暂时没连上"
                showBubble(error.localizedDescription)
                nextObservation = Date().addingTimeInterval(min(300, preferences.interval * pow(2, Double(min(failures, 3)))))
            }
        }
    }

    func showBubble(_ text: String) {
        bubbleTask?.cancel(); bubble = text
        bubbleTask = Task {
            try? await Task.sleep(for: .seconds(25))
            guard !Task.isCancelled else { return }; bubble = ""
        }
    }

    func saveSystemPrompt(_ text: String) throws {
        guard !loadFailed else { throw FishError.message("请先修复本地记录，再保存提示词。") }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw FishError.message("系统提示词不能为空。") }
        var updated = preferences
        updated.systemPrompt = text == (try PromptBuilder.defaultSystemPrompt()) ? nil : text
        try store.save(SavedState(preferences: updated, messages: messages, memories: memories))
        preferences = updated
    }

    func saveConnection(_ configuration: APIConfiguration) throws {
        guard !loadFailed else { throw FishError.message("请先修复本地记录，再保存配置。") }
        var updated = preferences
        updated.connection = try configuration.validated()
        try store.save(SavedState(preferences: updated, messages: messages, memories: memories))
        cancel()
        preferences = updated
        failures = 0; error = nil; status = hasKey ? "连接配置已保存" : "等待配置 API Key"
    }

    func attachImage() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .webP, .gif, .heic]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let values = try url.resourceValues(forKeys: [.fileSizeKey])
                guard (values.fileSize ?? 0) <= 32 * 1024 * 1024 else { throw FishError.message("请选择小于 32 MB 的图片。") }
                guard let image = NSImage(contentsOf: url) else { throw FishError.message("无法读取这张图片。") }
                let ratio = min(1, 1600 / max(image.size.width, image.size.height))
                let size = NSSize(width: max(1, image.size.width * ratio), height: max(1, image.size.height * ratio))
                let resized = NSImage(size: size, flipped: false) { rect in image.draw(in: rect); return true }
                guard let tiff = resized.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                      let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { throw FishError.message("图片转换失败。") }
                attachment = data; attachmentName = url.lastPathComponent
            } catch { self.error = error.localizedDescription }
        }
    }

    func importTheme() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.title = "选择包含 index.json 和动画 PNG 的主题文件夹"
        guard panel.runModal() == .OK, let source = panel.url else { return }
        do {
            let data = try Data(contentsOf: source.appendingPathComponent("index.json"))
            let index = try JSONDecoder().decode([String: Int].self, from: data)
            guard !index.isEmpty, index.allSatisfy({ !$0.key.contains("/") && !$0.key.contains("..") && (1...100).contains($0.value) }) else { throw FishError.message("主题索引无效。") }
            let name = source.lastPathComponent + "-" + UUID().uuidString.prefix(6)
            let destination = themeRoot.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            do {
                try data.write(to: destination.appendingPathComponent("index.json"))
                for (animation, count) in index {
                    for frame in 1...count {
                        let file = "\(animation)_\(frame).png"
                        guard NSImage(contentsOf: source.appendingPathComponent(file)) != nil else { throw FishError.message("主题缺少有效图片：\(file)") }
                        try FileManager.default.copyItem(at: source.appendingPathComponent(file), to: destination.appendingPathComponent(file))
                    }
                }
                if FileManager.default.fileExists(atPath: source.appendingPathComponent("Character.md").path) {
                    try FileManager.default.copyItem(at: source.appendingPathComponent("Character.md"), to: destination.appendingPathComponent("Character.md"))
                }
            } catch { try? FileManager.default.removeItem(at: destination); throw error }
            themes = FishTheme.builtins + FishTheme.imported(from: themeRoot)
            chooseTheme(name)
        } catch { self.error = "主题导入失败：\(error.localizedDescription)" }
    }
}
