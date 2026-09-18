import SwiftUI

private let ink = Color(red: 0.10, green: 0.22, blue: 0.28)
private let ocean = Color(red: 0.05, green: 0.48, blue: 0.63)

struct MainView: View {
    @ObservedObject var model: FishModel
    @State private var selection = "chat"
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 9) {
                    Image(systemName: "fish.fill").font(.title2).foregroundStyle(ocean)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("小肥鱼").font(.system(size: 18, weight: .bold, design: .rounded))
                        Text("FAT FISH FAIRY").font(.system(size: 8, weight: .semibold)).tracking(1.8).foregroundStyle(.secondary)
                    }
                }.padding(.bottom, 30).padding(.top, 14)
                nav("chat", "聊两句", "bubble.left.and.bubble.right")
                nav("memory", "小鱼的记忆", "sparkles")
                nav("appearance", "换个样子", "paintpalette")
                nav("settings", "设置", "slider.horizontal.3")
                Spacer()
                ThemeArtwork(theme: model.theme, activity: model.activity).frame(width: 135, height: 115).frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 7) {
                    Label(model.preferences.automatic ? "正在陪伴你" : "随时陪你摸鱼", systemImage: "circle.fill")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(ocean)
                    Text("给忙碌的桌面，\n留一点发呆的空间。").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
            }.padding(20).frame(width: 202).background(Color(red: 0.91, green: 0.96, blue: 0.965))
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title).font(.system(size: 23, weight: .bold, design: .rounded))
                        Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 5) { Circle().fill(model.hasKey ? Color.green : Color.orange).frame(width: 6, height: 6); Text("DeepSeek Flash").font(.system(size: 10, weight: .medium)) }
                        .padding(.horizontal, 10).padding(.vertical, 7).background(.white, in: Capsule())
                }.padding(26)
                Divider().opacity(0.6)
                if let error = model.error {
                    HStack(alignment: .top) {
                        Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                        Text(error).font(.system(size: 12)).textSelection(.enabled)
                        Spacer()
                        Button { model.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                    }.padding(12).background(Color.orange.opacity(0.08))
                }
                Group {
                    switch selection {
                    case "memory": memoryView
                    case "appearance": appearanceView
                    case "settings": settingsView
                    default: chatView
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.background(Color(red: 0.975, green: 0.985, blue: 0.986))
        }.foregroundStyle(ink).tint(ocean).frame(minWidth: 830, minHeight: 630)
            .preferredColorScheme(.light)
    }
    private var title: String { ["chat": "今天，也一起摸鱼。", "memory": "你说的，我记着呢。", "appearance": "今天想见哪条鱼？", "settings": "舒服地待在你身边。"][selection]! }
    private var subtitle: String { ["chat": "一只会看屏幕、会聊天，还有点小脾气的桌面伙伴。", "memory": "只记住你主动分享的偏好，随时可以忘掉。", "appearance": "一点颜色，一点性格，都是你的小肥鱼。", "settings": "让陪伴的节奏，刚刚好。"][selection]! }
    private func nav(_ id: String, _ label: String, _ icon: String) -> some View {
        Button { selection = id } label: {
            HStack(spacing: 11) { Image(systemName: icon).frame(width: 18); Text(label); Spacer() }
                .font(.system(size: 13, weight: selection == id ? .semibold : .regular)).padding(12)
                .foregroundStyle(selection == id ? ocean : ink.opacity(0.65))
                .background(selection == id ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }
    private var chatView: some View {
        VStack(spacing: 0) {
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if model.messages.isEmpty {
                            VStack(spacing: 12) {
                                ThemeArtwork(theme: model.theme, activity: "happy").frame(width: 185, height: 150)
                                Text("本肥鱼已就位。").font(.system(size: 20, weight: .semibold, design: .rounded))
                                Text("你忙你的，我陪我的。\n有什么想吐槽的，也可以跟我说。").font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
                                HStack(spacing: 8) {
                                    suggestion("打个招呼")
                                    suggestion("记住我喜欢喝拿铁")
                                }.padding(.top, 8)
                            }.frame(maxWidth: .infinity).padding(.top, 28)
                        }
                        ForEach(model.messages) { message in
                            HStack(alignment: .top, spacing: 10) {
                                if message.role == "user" { Spacer(minLength: 60) }
                                else { Image(systemName: "fish.fill").foregroundStyle(ocean).padding(8).background(ocean.opacity(0.08), in: Circle()) }
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(message.role == "user" ? "你" : "小肥鱼").fontWeight(.semibold)
                                        if message.observation { Text("· 看了看屏幕") }
                                        Spacer()
                                        Text(message.date, style: .time)
                                    }.font(.system(size: 10)).foregroundStyle(.secondary)
                                    Text(message.text).font(.system(size: 13)).lineSpacing(5).textSelection(.enabled)
                                }.padding(14).background(message.role == "user" ? ocean.opacity(0.09) : .white, in: RoundedRectangle(cornerRadius: 14))
                                if message.role != "user" { Spacer(minLength: 28) }
                            }.id(message.id)
                        }
                        if model.busy { HStack(spacing: 8) { ProgressView().controlSize(.small); Text(model.status).font(.system(size: 12)).foregroundStyle(.secondary); Button("取消") { model.cancel() }.buttonStyle(.borderless) }.id("busy") }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(24)
                }.onChange(of: model.messages.count) { _, _ in withAnimation { reader.scrollTo("bottom", anchor: .bottom) } }
                    .onChange(of: model.busy) { _, _ in withAnimation { reader.scrollTo("bottom", anchor: .bottom) } }
            }
            VStack(alignment: .leading, spacing: 10) {
                if let name = model.attachmentName {
                    HStack { Image(systemName: "photo"); Text(name).lineLimit(1); Button { model.attachment = nil; model.attachmentName = nil } label: { Image(systemName: "xmark.circle.fill") } }.font(.system(size: 11)).buttonStyle(.plain)
                }
                HStack(alignment: .bottom, spacing: 10) {
                    Button { model.attachImage() } label: { Image(systemName: "photo.badge.plus").font(.system(size: 18)) }.buttonStyle(.plain).help("附加图片，让小肥鱼看看").accessibilityLabel("附加图片").disabled(model.busy)
                    TextField("跟小肥鱼说点什么…", text: $model.draft, axis: .vertical).textFieldStyle(.plain).lineLimit(1...5).font(.system(size: 13))
                        .onSubmit { model.send() }.accessibilityLabel("聊天输入")
                    Button { model.send() } label: { Image(systemName: "arrow.up").font(.system(size: 14, weight: .bold)).frame(width: 29, height: 29) }
                        .buttonStyle(.borderedProminent).clipShape(RoundedRectangle(cornerRadius: 9)).keyboardShortcut(.return, modifiers: .command)
                        .disabled(model.busy || (model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.attachment == nil)).accessibilityLabel("发送")
                }.padding(13).background(.white, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(ocean.opacity(0.17)))
                HStack {
                    Button { model.observe() } label: { Label("看一眼屏幕", systemImage: "viewfinder") }.disabled(model.busy)
                    Spacer()
                    Button(model.preferences.automatic ? "暂停观察" : "开启自动观察") {
                        if model.screenPermission { model.setAutomatic(!model.preferences.automatic) } else { selection = "settings" }
                    }
                }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(ocean)
            }.padding(20).background(Color(red: 0.95, green: 0.975, blue: 0.98))
        }
    }
    private func suggestion(_ text: String) -> some View {
        Button(text) { model.draft = text; model.send() }.font(.system(size: 11)).buttonStyle(.bordered).disabled(model.busy)
    }
    private var memoryView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label("跨重启保留 · 最多 60 条", systemImage: "externaldrive").font(.system(size: 12)).foregroundStyle(.secondary)
                if model.memories.isEmpty {
                    VStack(spacing: 12) { Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(ocean); Text("还没有小秘密").font(.headline); Text("聊聊你喜欢的东西，我会慢慢记住。").font(.system(size: 13)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(55)
                }
                ForEach(model.memories) { memory in
                    HStack(alignment: .top) {
                        Image(systemName: "bubble.left").foregroundStyle(ocean)
                        VStack(alignment: .leading, spacing: 6) { Text(memory.text).font(.system(size: 13)).textSelection(.enabled); Text(memory.date, style: .date).font(.system(size: 10)).foregroundStyle(.secondary) }
                        Spacer()
                        Button("忘掉") { model.memories.removeAll { $0.id == memory.id }; model.persist() }.buttonStyle(.borderless).font(.system(size: 11))
                    }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 12))
                }
            }.padding(26)
        }
    }
    private var appearanceView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], spacing: 14) {
                    ForEach(model.themes) { theme in
                        Button { model.chooseTheme(theme.id) } label: {
                            VStack(spacing: 4) {
                                ThemeArtwork(theme: theme, activity: "idle").frame(height: 110)
                                HStack { Text(theme.name).lineLimit(1); if model.preferences.theme == theme.id { Image(systemName: "checkmark.circle.fill") } }.font(.system(size: 12, weight: .medium))
                            }.padding(14).frame(maxWidth: .infinity).background(.white, in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(model.preferences.theme == theme.id ? ocean : .clear, lineWidth: 2))
                        }.buttonStyle(.plain)
                    }
                }
                Text("切换角色会开始新对话，记忆仍然保留。").font(.system(size: 11)).foregroundStyle(.secondary)
                card("桌面上的大小") {
                    HStack { Text("小巧"); Slider(value: $model.preferences.petSize, in: 120...245, step: 5) { _ in model.persist() }; Text("圆滚滚") }.font(.system(size: 12))
                }
                card("带上你喜欢的角色") {
                    Text("兼容原版的 index.json、Character.md 和逐帧 PNG 主题。原仓库图片仅供测试，请遵守素材授权。").font(.system(size: 12)).foregroundStyle(.secondary)
                    Button("导入主题文件夹…") { model.importTheme() }
                }
            }.padding(26)
        }
    }
    private var settingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                card("观察与陪伴") {
                    Toggle("自动观察屏幕", isOn: Binding(get: { model.preferences.automatic }, set: { model.setAutomatic($0) }))
                    Text("开启后，屏幕截图会发送到 DeepSeek 进行识别。截图不保存到磁盘；锁屏和休眠时暂停。").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack { Text("观察间隔"); Spacer(); Picker("观察间隔", selection: $model.preferences.interval) { Text("30 秒").tag(30.0); Text("1 分钟").tag(60.0); Text("2 分钟").tag(120.0); Text("5 分钟").tag(300.0) }.labelsHidden().frame(width: 120).onChange(of: model.preferences.interval) { _, _ in model.persist() } }
                    Toggle("观察所有显示器", isOn: $model.preferences.allDisplays).onChange(of: model.preferences.allDisplays) { _, _ in model.persist() }
                    HStack { Label(model.screenPermission ? "屏幕录制已授权" : "尚未授权屏幕录制", systemImage: model.screenPermission ? "checkmark.shield" : "lock.rectangle"); Spacer(); Button(model.screenPermission ? "系统设置" : "去授权") { model.requestPermission() } }
                    Text("授权后如仍无法截图，请退出并重新打开应用。").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                card("DeepSeek") {
                    HStack { Text("识图与对话"); Spacer(); Text("deepseek-flash").font(.system(size: 12, design: .monospaced)).foregroundStyle(ocean) }
                    HStack { Label(model.hasKey ? "密钥已读取" : "未配置密钥", systemImage: model.hasKey ? "checkmark.circle.fill" : "key").foregroundStyle(model.hasKey ? ocean : .orange); Spacer(); Button("选择 .secret…") { model.chooseCredentials() } }
                    Text("密钥仅在本机读取，不写入聊天记录或应用包。").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                card("小肥鱼的性格") {
                    TextEditor(text: $model.preferences.personality).font(.system(size: 12)).frame(height: 80).scrollContentBackground(.hidden).padding(8).background(Color.black.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
                        .onChange(of: model.preferences.personality) { _, _ in model.persist() }
                    Text("用于内置小肥鱼；导入主题优先使用自己的 Character.md。").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                HStack {
                    Button("打开本地数据") { NSWorkspace.shared.open(model.store.directory) }
                    Spacer()
                    Button(model.petVisible ? "隐藏桌面小鱼" : "显示桌面小鱼") { AppDelegate.shared?.togglePet() }
                    Button("退出小肥鱼") { NSApp.terminate(nil) }
                }.font(.system(size: 11))
            }.font(.system(size: 12)).padding(26)
        }
    }
    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) { Text(title).font(.system(size: 13, weight: .semibold)); content() }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 14))
    }
}
