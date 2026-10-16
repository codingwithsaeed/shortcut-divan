// Builds Resources/AppIcon.icon, an Icon Composer icon: macOS renders its layers as Liquid
// Glass (light, dark, tinted and clear looks) and Xcode makes the older-macOS icon from it.
//   back:  a purple keycap, tilted
//   front: a clear glass keycap with a pink ⌘
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

// Two keycaps on a dark ground: a tinted one behind, tilted, and a clear glass one in front.
let back = CGRect(x: 170, y: 170, width: 440, height: 440)
try layer("back.png") { cg in
    rotated(cg, around: CGPoint(x: back.midX, y: back.midY), degrees: -12) {
        cg.addPath(CGPath(roundedRect: back, cornerWidth: 112, cornerHeight: 112, transform: nil))
        cg.fillPath()
    }
}

let key = CGRect(x: 372, y: 372, width: 480, height: 480)
try layer("key.png") { cg in
    cg.addPath(CGPath(roundedRect: key, cornerWidth: 122, cornerHeight: 122, transform: nil))
    cg.fillPath()
}

// ⌘ on the front key.
try layer("command.png") { cg in
    let font = NSFont.systemFont(ofSize: 300, weight: .bold)
    let glyph = NSAttributedString(string: "⌘", attributes: [.font: font, .foregroundColor: NSColor.white])
    let size = glyph.size()
    // NSString drawing expects a flipped context here.
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    glyph.draw(at: NSPoint(x: key.midX - size.width / 2, y: key.midY - size.height / 2 - 8))
}

let icon: [String: Any] = [
    "fill": [
        "linear-gradient": ["display-p3:0.17255,0.12157,0.29412,1.00000", "display-p3:0.06667,0.05098,0.12157,1.00000"],
        "orientation": ["start": ["x": 0.5, "y": 0], "stop": ["x": 0.5, "y": 1]],
    ],
    "groups": [
        [
            "name": "Front",
            "layers": [
                ["name": "Command", "image-name": "command.png", "glass": false,
                 "fill": ["automatic-gradient": "display-p3:0.92157,0.38039,0.56471,1.00000"]],
                ["name": "Key", "image-name": "key.png", "glass": true,
                 "fill": ["automatic-gradient": "display-p3:1.00000,1.00000,1.00000,0.85000"]],
            ],
            "shadow": ["kind": "neutral", "opacity": 0.6],
            "translucency": ["enabled": true, "value": 0.3],
            "specular": true,
        ],
        [
            "name": "Back",
            "layers": [
                ["name": "Back", "image-name": "back.png", "glass": true,
                 "fill": ["automatic-gradient": "display-p3:0.61961,0.40000,0.95686,1.00000"]],
            ],
            "shadow": ["kind": "layer-color", "opacity": 0.5],
            "translucency": ["enabled": true, "value": 0.2],
            "specular": true,
        ],
    ],
    "supported-platforms": ["squares": ["macOS"]],
]
try JSONSerialization.data(withJSONObject: icon, options: [.prettyPrinted, .sortedKeys])
    .write(to: root.appendingPathComponent("icon.json"))
print("wrote \(root.path)")
