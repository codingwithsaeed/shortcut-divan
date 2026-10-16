// Builds Resources/AppIcon.icon, an Icon Composer icon: macOS renders its layers as Liquid
// Glass (light, dark, tinted and clear looks) and Xcode makes the older-macOS icon from it.
//   one glass keycap with ⌥ and ⌘ on it, in the app's Rosé Pine colors, light and dark
// Run from the repo root after changing it: swift scripts/make-icon.swift
import AppKit

let canvas: CGFloat = 1024
let root = URL(fileURLWithPath: "Resources/AppIcon.icon")
let assets = root.appendingPathComponent("Assets")
try? FileManager.default.removeItem(at: root)
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

// A white shape on a transparent 1024 canvas, drawn in top-left coordinates.
func layer(_ name: String, _ draw: (CGContext) -> Void) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    let cg = context.cgContext
    cg.translateBy(x: 0, y: canvas)
    cg.scaleBy(x: 1, y: -1)
    cg.setFillColor(.white)
    draw(cg)
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: assets.appendingPathComponent(name))
}

func rotated(_ cg: CGContext, around center: CGPoint, degrees: CGFloat, _ draw: () -> Void) {
    cg.saveGState()
    cg.translateBy(x: center.x, y: center.y)
    cg.rotate(by: degrees * .pi / 180)
    cg.translateBy(x: -center.x, y: -center.y)
    draw()
    cg.restoreGState()
}

// One big glass keycap in the middle.
let key = CGRect(x: 232, y: 232, width: 560, height: 560)
try layer("key.png") { cg in
    cg.addPath(CGPath(roundedRect: key, cornerWidth: 140, cornerHeight: 140, transform: nil))
    cg.fillPath()
}

// ⌥ and ⌘ side by side on it.
try layer("command.png") { cg in
    let font = NSFont.systemFont(ofSize: 230, weight: .semibold)
    let glyph = NSAttributedString(string: "⌥⌘", attributes: [.font: font, .foregroundColor: NSColor.white, .kern: 24])
    let size = glyph.size()
    // NSString drawing expects a flipped context here.
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    glyph.draw(at: NSPoint(x: key.midX - size.width / 2 + 12, y: key.midY - size.height / 2 - 6))
}

// Rosé Pine colors, as in the app: Dawn in light mode, the night palette in dark mode.
func p3(_ hex: UInt32, _ alpha: Double = 1) -> String {
    let c = [hex >> 16 & 0xff, hex >> 8 & 0xff, hex & 0xff].map { String(format: "%.5f", Double($0) / 255) }
    return "display-p3:\(c.joined(separator: ",")),\(String(format: "%.5f", alpha))"
}
func gradient(_ top: UInt32, _ bottom: UInt32) -> [String: Any] {
    ["linear-gradient": [p3(top), p3(bottom)], "orientation": ["start": ["x": 0.5, "y": 0], "stop": ["x": 0.5, "y": 1]]]
}
func appearances(light: Any, dark: Any) -> [[String: Any]] {
    [["value": light], ["appearance": "dark", "value": dark]]
}

let icon: [String: Any] = [
    "fill-specializations": appearances(light: gradient(0xe4d5f2, 0xc4a7e7), dark: gradient(0x393552, 0x191724)),
    "groups": [
        [
            "name": "Key",
            "layers": [
                ["name": "Glyphs", "image-name": "command.png", "glass": false,
                 "fill-specializations": appearances(light: ["solid": p3(0x57408a)], dark: ["solid": p3(0xffffff)])],
                ["name": "Key", "image-name": "key.png", "glass": true,
                 "fill-specializations": appearances(light: ["automatic-gradient": p3(0xfffaf3, 0.95)],
                                                     dark: ["automatic-gradient": p3(0x403d52, 0.9)])],
            ],
            "shadow": ["kind": "neutral", "opacity": 0.45],
            "translucency": ["enabled": true, "value": 0.25],
            "specular": true,
        ],
    ],
    "supported-platforms": ["squares": ["macOS"]],
]
try JSONSerialization.data(withJSONObject: icon, options: [.prettyPrinted, .sortedKeys])
    .write(to: root.appendingPathComponent("icon.json"))
print("wrote \(root.path)")
