import AppKit
import ScreenCaptureKit

enum ScreenCapture {
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    @MainActor static func capture(allDisplays: Bool) async throws -> [Data] {
        guard hasPermission else { throw FishError.message("需要屏幕录制权限。请在设置中授权，然后重新打开小肥鱼。") }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let mainID = CGMainDisplayID()
        let displays = allDisplays ? content.displays : content.displays.filter { $0.displayID == mainID }
        guard !displays.isEmpty else { throw FishError.message("屏幕暂时不可用，解锁后会继续观察。") }
        var images: [Data] = []
        for display in displays {
            try Task.checkCancellation()
            let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            let config = SCStreamConfiguration()
            let scale = min(1.0, 1440.0 / Double(max(display.width, display.height)))
            config.width = Int(Double(display.width) * scale)
            config.height = Int(Double(display.height) * scale)
            config.showsCursor = false
            let cg = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let bitmap = NSBitmapImageRep(cgImage: cg)
            guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.72]) else { throw FishError.message("无法编码截图。") }
            images.append(data)
        }
        return images
    }
}
