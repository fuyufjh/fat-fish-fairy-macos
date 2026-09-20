import AppKit
import SwiftUI

@MainActor enum AppBrand {
    static let image: NSImage = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) { return image }
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) { return image }
        #endif
        return NSImage(size: NSSize(width: 32, height: 32))
    }()

    static func menuBarIcon(from source: NSImage) -> NSImage {
        let icon = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.22, yRadius: rect.height * 0.22).addClip()
            source.draw(in: rect)
            return true
        }
        icon.isTemplate = false
        return icon
    }
}

struct BrandIcon: View {
    let size: CGFloat
    var body: some View {
        Image(nsImage: AppBrand.image).resizable().scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
            .accessibilityLabel("小肥鱼")
    }
}
