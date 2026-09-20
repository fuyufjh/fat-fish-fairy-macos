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
