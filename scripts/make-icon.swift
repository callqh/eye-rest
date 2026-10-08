import AppKit
let directory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let rect = NSRect(x: 64, y: 64, width: 896, height: 896)
        NSColor(calibratedRed: 0.28, green: 0.40, blue: 0.57, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 205, yRadius: 205).fill()
        NSColor(calibratedRed: 0.92, green: 0.96, blue: 1, alpha: 1).setStroke()
        let path = NSBezierPath(); path.lineWidth = 66; path.lineCapStyle = .round
        path.move(to: NSPoint(x: 240, y: 535)); path.curve(to: NSPoint(x: 432, y: 580), controlPoint1: NSPoint(x: 262, y: 815), controlPoint2: NSPoint(x: 380, y: 800))
        path.move(to: NSPoint(x: 592, y: 580)); path.curve(to: NSPoint(x: 784, y: 535), controlPoint1: NSPoint(x: 644, y: 800), controlPoint2: NSPoint(x: 762, y: 815))
        path.move(to: NSPoint(x: 350, y: 400)); path.curve(to: NSPoint(x: 674, y: 400), controlPoint1: NSPoint(x: 432, y: 250), controlPoint2: NSPoint(x: 592, y: 250)); path.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let url = URL(fileURLWithPath: directory).appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
}
