// Draws the app icon (a ⌘ keycap on a Rose Pine gradient) into Resources/Assets.xcassets.
// Run from the repo root after changing it: swift scripts/make-icon.swift
import AppKit

func draw(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    func hex(_ v: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat(v >> 16 & 0xff) / 255, green: CGFloat(v >> 8 & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }
    // macOS icon grid: 824pt rounded square centred in 1024.
    let body = NSBezierPath(roundedRect: NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s),
                            xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(colors: [hex(0x26233a), hex(0x191724)])!.draw(in: body, angle: -90)
    // Keycap.
    let cap = NSRect(x: 252 * s, y: 270 * s, width: 520 * s, height: 520 * s)
    let shadow = NSBezierPath(roundedRect: cap.offsetBy(dx: 0, dy: -26 * s), xRadius: 110 * s, yRadius: 110 * s)
    hex(0x524f67).setFill(); shadow.fill()
    let top = NSBezierPath(roundedRect: cap, xRadius: 110 * s, yRadius: 110 * s)
    NSGradient(colors: [hex(0xc4a7e7), hex(0xeb6f92)])!.draw(in: top, angle: -60)
    // ⌘ glyph.
    let font = NSFont.systemFont(ofSize: 330 * s, weight: .semibold)
    let glyph = NSAttributedString(string: "⌘", attributes: [.font: font, .foregroundColor: hex(0x191724)])
    let size = glyph.size()
    glyph.draw(at: NSPoint(x: cap.midX - size.width / 2, y: cap.midY - size.height / 2 + 6 * s))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let dir = URL(fileURLWithPath: "Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
var images: [[String: String]] = []
for pt in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(pt)x\(pt)@\(scale)x.png"
        try draw(pt * scale).write(to: dir.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(pt)x\(pt)", "scale": "\(scale)x", "filename": name])
    }
}
let info: [String: Any] = ["author": "xcode", "version": 1]
try JSONSerialization.data(withJSONObject: ["images": images, "info": info], options: [.prettyPrinted, .sortedKeys])
    .write(to: dir.appendingPathComponent("Contents.json"))
try #"{ "info" : { "author" : "xcode", "version" : 1 } }"#.write(
    to: dir.deletingLastPathComponent().appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
