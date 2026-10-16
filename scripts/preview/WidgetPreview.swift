// Renders the widget at each desktop size, light and dark, into previews/*.png, so a change
// can be looked at without a Mac. The Build workflow runs it and keeps the images:
//   swiftc -parse-as-library -o preview scripts/preview/WidgetPreview.swift Widget/Views.swift Widget/Paging.swift Shared/*.swift
import AppKit
import CoreText
import SwiftUI
import WidgetKit

private func row(_ keys: String, _ desc: String) -> Shortcut { Shortcut(keys: keys, desc: desc) }

// Long descriptions and long keys, to show that rows never run past the widget's edge.
private let sections = [
    Section(title: "macOS", accent: "iris", rows: [
        row("⌘␣", "Spotlight search"), row("⌘Z / ⇧⌘Z", "undo / redo"), row("⌃⌘␣", "emoji & symbols"),
        row("⇧⌘3 / ⇧⌘4", "screenshot: screen / area"), row("⌘⇥", "switch apps"), row("⌘`", "next window, same app"),
        row("⌘W", "close window"), row("⌘Q", "quit app"), row("⌘H", "hide app"), row("⌃⌘F", "full screen"),
        row("⌘,", "app settings"),
    ]),
    Section(title: "Laravel · Docker", accent: "pine", rows: [
        row("art cmd", "php artisan"), row("tf Name", "test --filter"), row("dcu / dcd", "compose up / down"),
        row("dps / dlog", "status / logs"), row("tinker", "tinker"),
    ]),
]

@MainActor private func render(_ family: WidgetFamily, _ size: CGSize, _ name: String, dark: Bool) {
    let entry = Entry(date: .now, sections: sections, key: "", page: 0)
    let view = SectionsContent(entry: entry, family: family)
        .padding(16)
        .frame(width: size.width, height: size.height)
        .background(dark ? Color(white: 0.12) : Color(white: 0.94))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .environment(\.colorScheme, dark ? .dark : .light)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: "previews/\(name)-\(dark ? "dark" : "light").png"))
}

@main enum WidgetPreview {
    @MainActor static func main() {
        try? FileManager.default.createDirectory(atPath: "previews", withIntermediateDirectories: true)
        // Not an app bundle, so Inter is registered from the repository's copy.
        for name in (try? FileManager.default.contentsOfDirectory(atPath: "Resources/Fonts")) ?? [] where name.hasSuffix(".ttf") {
            CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: "Resources/Fonts/" + name) as CFURL, .process, nil)
        }
        for dark in [false, true] {
            render(.systemSmall, CGSize(width: 170, height: 170), "small", dark: dark)
            render(.systemMedium, CGSize(width: 345, height: 160), "medium", dark: dark)
            render(.systemLarge, CGSize(width: 345, height: 345), "large", dark: dark)
            render(.systemExtraLarge, CGSize(width: 705, height: 345), "extra-large", dark: dark)
        }
    }
}
