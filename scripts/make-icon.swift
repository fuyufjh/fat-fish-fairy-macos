import AppKit

let folder = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 512, y: CGFloat(pixels) / 512)
        NSColor(calibratedRed: 0.90, green: 0.97, blue: 0.99, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 20, y: 20, width: 472, height: 472), xRadius: 104, yRadius: 104).fill()
        NSColor(calibratedRed: 0.12, green: 0.72, blue: 0.88, alpha: 1).setFill()
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 330, y: 235)); tail.curve(to: NSPoint(x: 447, y: 325), controlPoint1: NSPoint(x: 390, y: 250), controlPoint2: NSPoint(x: 397, y: 346))
        tail.curve(to: NSPoint(x: 438, y: 234), controlPoint1: NSPoint(x: 480, y: 315), controlPoint2: NSPoint(x: 474, y: 258))
        tail.curve(to: NSPoint(x: 461, y: 180), controlPoint1: NSPoint(x: 485, y: 211), controlPoint2: NSPoint(x: 480, y: 189))
        tail.curve(to: NSPoint(x: 330, y: 235), controlPoint1: NSPoint(x: 412, y: 153), controlPoint2: NSPoint(x: 378, y: 190)); tail.fill()
        NSBezierPath(ovalIn: NSRect(x: 65, y: 119, width: 318, height: 262)).fill()
        NSColor.white.setFill(); NSBezierPath(ovalIn: NSRect(x: 95, y: 130, width: 254, height: 124)).fill()
        NSColor(calibratedWhite: 1, alpha: 0.4).setFill(); NSBezierPath(ovalIn: NSRect(x: 125, y: 324, width: 86, height: 22)).fill()
        NSColor(calibratedRed: 0.07, green: 0.22, blue: 0.30, alpha: 1).setFill()
        for x in [139, 238] { NSBezierPath(roundedRect: NSRect(x: x, y: 245, width: 17, height: 27), xRadius: 8, yRadius: 8).fill() }
        let mouth = NSBezierPath(); mouth.move(to: NSPoint(x: 184, y: 234)); mouth.curve(to: NSPoint(x: 210, y: 234), controlPoint1: NSPoint(x: 188, y: 216), controlPoint2: NSPoint(x: 206, y: 216)); mouth.lineWidth = 5; NSColor(calibratedRed: 0.07, green: 0.22, blue: 0.30, alpha: 1).setStroke(); mouth.stroke()
        NSColor.systemPink.withAlphaComponent(0.28).setFill()
        for x in [115, 262] { NSBezierPath(ovalIn: NSRect(x: x, y: 225, width: 35, height: 15)).fill() }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: folder + "/icon_\(size)x\(size)\(suffix).png"))
    }
}
