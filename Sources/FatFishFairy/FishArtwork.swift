import SwiftUI
import AppKit

@MainActor final class ThemeImageCache {
    static let shared = ThemeImageCache()
    private let cache = NSCache<NSURL, NSImage>()
    func image(_ url: URL) -> NSImage? {
        if let image = cache.object(forKey: url as NSURL) { return image }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: url as NSURL); return image
    }
}

struct ThemeArtwork: View {
    let theme: FishTheme
    var activity = "idle"
    var body: some View {
        if let folder = theme.directory {
            TimelineView(.periodic(from: .now, by: 0.4)) { context in
                let action = theme.animations[activity] != nil ? activity : (theme.animations.keys.sorted().first ?? "idle")
                let count = max(1, theme.animations[action] ?? 1)
                let frame = Int(context.date.timeIntervalSinceReferenceDate / 0.4) % count + 1
                if let image = ThemeImageCache.shared.image(folder.appendingPathComponent("\(action)_\(frame).png")) {
                    Image(nsImage: image).resizable().scaledToFit()
                } else { Color.clear }
            }
        } else { Color.clear }
    }
}

struct PetView: View {
    @ObservedObject var model: FishModel
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            if !model.bubble.isEmpty {
                PetSpeechBubble(text: model.bubble)
                    .onTapGesture { AppDelegate.shared?.showWindow() }
                    .help("点击打开完整对话")
            }
            ThemeArtwork(theme: model.theme, activity: model.activity)
                .frame(width: model.preferences.petSize, height: model.preferences.petSize * 0.86)
                .overlay(PetDragArea())
            Text(model.busy ? model.status : (model.preferences.automatic ? "● 陪伴中" : "Ⅱ 观察已暂停"))
                .font(.system(size: 10, weight: .medium)).foregroundStyle(.primary).padding(.horizontal, 9).padding(.vertical, 4)
                .background(.regularMaterial, in: Capsule()).padding(.bottom, 10)
        }.padding(.horizontal, 14).frame(width: 330, height: 365)
    }
}

struct PetDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 { AppDelegate.shared?.showWindow(); return }
            window?.performDrag(with: event)
            AppDelegate.shared?.savePetPosition()
        }
        override func rightMouseDown(with event: NSEvent) {
            if let menu = AppDelegate.shared?.makeMenu() { NSMenu.popUpContextMenu(menu, with: event, for: self) }
        }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
        override func accessibilityLabel() -> String? { "小肥鱼：拖动移动，双击聊天，右键菜单" }
        override func isAccessibilityElement() -> Bool { true }
        override func accessibilityRole() -> NSAccessibility.Role? { .image }
    }
}
