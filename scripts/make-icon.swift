// Renders Assets/AppIcon.icns: a filled dot with a small triangle, on a dark rounded square.
import AppKit
let out = CommandLine.arguments[1]
let set = out + "/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px), inset = s * 0.1, r = s - inset * 2
    let bg = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: r, height: r), xRadius: r * 0.225, yRadius: r * 0.225)
    NSGradient(starting: NSColor(white: 0.20, alpha: 1), ending: NSColor(white: 0.07, alpha: 1))!.draw(in: bg, angle: -90)
    NSColor.white.setFill()
    let d = s * 0.26, cx = s * 0.60, cy = s * 0.5
    NSBezierPath(ovalIn: NSRect(x: cx - d / 2, y: cy - d / 2, width: d, height: d)).fill()
    let t = NSBezierPath(), th = s * 0.16, tx = s * 0.30
    t.move(to: NSPoint(x: tx - th * 0.45, y: cy))
    t.line(to: NSPoint(x: tx + th * 0.45, y: cy + th / 2))
    t.line(to: NSPoint(x: tx + th * 0.45, y: cy - th / 2))
    t.close()
    NSColor(white: 1, alpha: 0.55).setFill(); t.fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).write(to: URL(fileURLWithPath: "\(set)/icon_\(name).png"))
}
try! render(1024).write(to: URL(fileURLWithPath: out + "/icon.png"))
