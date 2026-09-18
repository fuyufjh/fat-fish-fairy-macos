import SwiftUI
import AppKit

struct WhaleTail: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.width * 0.12, y: r.height * 0.50))
        p.addCurve(to: CGPoint(x: r.width * 0.96, y: r.height * 0.10), control1: CGPoint(x: r.width * 0.55, y: r.height * 0.55), control2: CGPoint(x: r.width * 0.60, y: -r.height * 0.08))
        p.addQuadCurve(to: CGPoint(x: r.width * 0.85, y: r.height * 0.61), control: CGPoint(x: r.width * 1.10, y: r.height * 0.50))
        p.addQuadCurve(to: CGPoint(x: r.width * 0.95, y: r.height * 0.96), control: CGPoint(x: r.width * 1.10, y: r.height * 0.85))
        p.addQuadCurve(to: CGPoint(x: r.width * 0.12, y: r.height * 0.50), control: CGPoint(x: r.width * 0.40, y: r.height * 1.02))
        p.closeSubpath(); return p
    }
}

struct FishArtwork: View {
    var color: Color = .cyan
    var activity = "idle"
    var animated = true
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.06, paused: !animated)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let bob = animated ? sin(t * 2) * 3 : 0
            let blink = activity == "sleeping" || (animated && t.truncatingRemainder(dividingBy: 5.6) < 0.18)
            GeometryReader { proxy in
                let w = proxy.size.width
                ZStack {
                    Ellipse().fill(.black.opacity(0.08)).frame(width: w * 0.55, height: w * 0.06).offset(y: w * 0.34)
                    ZStack {
                        WhaleTail().fill(LinearGradient(colors: [color.opacity(0.9), color], startPoint: .top, endPoint: .bottom))
                            .frame(width: w * 0.30, height: w * 0.29).rotationEffect(.degrees(sin(t * 2.4) * 7)).offset(x: w * 0.32, y: w * 0.02)
                        Ellipse().fill(LinearGradient(colors: [color.opacity(0.72), color, color.opacity(0.92)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: w * 0.74, height: w * 0.57).offset(x: -w * 0.035)
                        Ellipse().fill(Color.white.opacity(0.85)).frame(width: w * 0.55, height: w * 0.27).offset(x: -w * 0.06, y: w * 0.125)
                        Ellipse().fill(.white.opacity(0.4)).frame(width: w * 0.22, height: w * 0.065).rotationEffect(.degrees(-24)).offset(x: -w * 0.15, y: -w * 0.16)
                        Ellipse().fill(color).frame(width: w * 0.20, height: w * 0.10).rotationEffect(.degrees(35 + sin(t * 2) * 5)).offset(x: w * 0.16, y: w * 0.17)
                        HStack(spacing: w * 0.16) {
                            ForEach(0..<2) { _ in
                                Capsule().fill(Color(red: 0.08, green: 0.18, blue: 0.24)).frame(width: w * 0.035, height: blink ? w * 0.013 : w * 0.058)
                                    .overlay(alignment: .topTrailing) { if !blink { Circle().fill(.white).frame(width: w * 0.011).padding(1) } }
                            }
                        }.offset(x: -w * 0.11, y: -w * 0.025)
                        HStack(spacing: w * 0.24) {
                            ForEach(0..<2) { _ in Ellipse().fill(Color.pink.opacity(0.32)).frame(width: w * 0.075, height: w * 0.035) }
                        }.offset(x: -w * 0.11, y: w * 0.035)
                        Text(activity == "happy" ? "◡" : "﹏").font(.system(size: w * 0.085, weight: .bold, design: .rounded)).foregroundStyle(Color(red: 0.08, green: 0.25, blue: 0.32)).offset(x: -w * 0.11, y: w * 0.02)
                        if activity == "thinking" {
                            Text("···").font(.system(size: w * 0.13, weight: .bold)).foregroundStyle(color).offset(x: w * 0.15, y: -w * 0.38)
                        } else if activity == "sleeping" {
                            Text("z z").font(.system(size: w * 0.09, weight: .medium, design: .rounded)).foregroundStyle(color.opacity(0.8)).offset(x: w * 0.17, y: -w * 0.35)
                        } else {
                            Capsule().fill(color.opacity(0.6)).frame(width: w * 0.025, height: w * 0.11).rotationEffect(.degrees(-20)).offset(x: -w * 0.035, y: -w * 0.35)
                            Capsule().fill(color.opacity(0.4)).frame(width: w * 0.025, height: w * 0.08).rotationEffect(.degrees(28)).offset(x: w * 0.035, y: -w * 0.335)
                        }
                    }.offset(y: bob).rotationEffect(.degrees(animated ? sin(t * 1.3) * 1.5 : 0))
                }.frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .accessibilityLabel("圆滚滚的小肥鱼")
    }
}

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
                } else { FishArtwork(color: Color(nsColor: theme.color), activity: activity) }
            }
        } else { FishArtwork(color: Color(nsColor: theme.color), activity: activity) }
    }
}

struct PetView: View {
    @ObservedObject var model: FishModel
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            if !model.bubble.isEmpty {
                Text(model.bubble).font(.system(size: 13, weight: .medium)).foregroundStyle(Color(red: 0.12, green: 0.21, blue: 0.26))
                    .lineLimit(5).padding(14).frame(maxWidth: 280, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.8)))
                    .shadow(color: .black.opacity(0.1), radius: 10, y: 3)
                    .onTapGesture { AppDelegate.shared?.showWindow() }
                    .help("点击打开完整对话")
            }
            ThemeArtwork(theme: model.theme, activity: model.activity)
                .frame(width: model.preferences.petSize, height: model.preferences.petSize * 0.86)
                .overlay(PetDragArea())
            Text(model.busy ? model.status : (model.preferences.automatic ? "● 陪伴中" : "Ⅱ 观察已暂停"))
                .font(.system(size: 10, weight: .medium)).padding(.horizontal, 9).padding(.vertical, 4)
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
