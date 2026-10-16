// The shortcut data, shared by the app and the widget.
//
// It lives in ~/Library/Application Support/Shortcut Divan/shortcuts.json. The app writes it;
// the sandboxed widget may read only that folder (see the widget's entitlements). Until the
// app has written it, both fall back to the bundled defaults in the system language.
import Foundation
import SwiftUI

struct Shortcut: Codable, Hashable {
    var keys: String
    var desc: String
    var only: String? = nil // rows tagged for another tool (e.g. "overlay") are kept but not shown
}

struct Section: Codable, Hashable, Identifiable {
    var title: String
    var accent: String
    var rows: [Shortcut]
    var id: String { title }
}

enum Shortcuts {
    // The real home folder, not the sandbox container.
    static var home: URL {
        let path = getpwuid(getuid()).flatMap { String(validatingCString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: path)
    }

    static var dataFile: URL {
        home.appendingPathComponent("Library/Application Support/Shortcut Divan/shortcuts.json")
    }

    static var defaultsFile: URL? {
        Bundle.main.url(forResource: "Defaults", withExtension: "json")
    }

    // The shown rows of every section.
    static func load() -> [Section] {
        loadAll().map { section in
            Section(title: section.title, accent: section.accent, rows: section.rows.filter { $0.only == nil })
        }
    }

    // Everything in the data file, or the defaults.
    static func loadAll() -> [Section] {
        for url in [dataFile, defaultsFile].compactMap({ $0 }) {
            if let data = try? Data(contentsOf: url), let sections = try? decode(data) {
                return sections
            }
        }
        return []
    }

    static func decode(_ data: Data) throws -> [Section] {
        try JSONDecoder().decode(File.self, from: data).sections
    }

    // Readable JSON in a hand-editable layout: one shortcut per line.
    static func format(_ sections: [Section]) -> String {
        func quote(_ text: String) -> String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .withoutEscapingSlashes
            return String(decoding: (try? encoder.encode(text)) ?? Data("\"\"".utf8), as: UTF8.self)
        }
        let body = sections.map { section in
            let rows = section.rows.map { row in
                let only = row.only.map { ", \"only\": \(quote($0))" } ?? ""
                return "        { \"keys\": \(quote(row.keys)), \"desc\": \(quote(row.desc))\(only) }"
            }
            return """
                {
                  "title": \(quote(section.title)),
                  "accent": \(quote(section.accent)),
                  "rows": \(rows.isEmpty ? "[]" : "[\n" + rows.joined(separator: ",\n") + "\n      ]")
                }
            """
        }
        return "{\n  \"sections\": [\n" + body.joined(separator: ",\n") + "\n  ]\n}\n"
    }

    static let accents = ["love", "gold", "rose", "pine", "foam", "iris"]

    private struct File: Codable { let sections: [Section] }
}

extension LayoutDirection {
    // Right to left when the app runs in Persian (AppKit doesn't flip SwiftUI on its own
    // unless the whole system is in a right-to-left language).
    static var app: LayoutDirection {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        return Locale.Language(identifier: language).characterDirection == .rightToLeft ? .rightToLeft : .leftToRight
    }
}

enum KeyText {
    // A narrow space after each modifier, so "⇧⌘D" doesn't read as one blob, kept
    // left-to-right inside Persian text. ␣ is barely visible small, so it's spelled out,
    // as "Space" in every language: that's what the key says.
    static func spaced(_ keys: String) -> String {
        let symbols: Set<Character> = ["⌃", "⌥", "⇧", "⌘", "⇥", "↩", "⎋", "⌫"]
        let keys = keys.replacingOccurrences(of: "␣", with: "Space")
        var out = ""
        for (index, char) in zip(keys.indices, keys) {
            out.append(char)
            let next = keys.index(after: index)
            if symbols.contains(char), next < keys.endIndex, keys[next] != " " {
                out.append("\u{2004}")
            }
        }
        return "\u{2066}" + out + "\u{2069}"
    }
}

// Rosé Pine (dark) and Rosé Pine Dawn (light), with darker light accents so they stay
// readable on a light widget.
extension Color {
    static func rosePine(_ name: String) -> Color {
        let (dark, light): (UInt32, UInt32) = switch name {
        case "love": (0xeb6f92, 0x9a2f52)
        case "gold": (0xf6c177, 0x8a4f00)
        case "rose": (0xebbcba, 0x9a3c36)
        case "pine": (0x5fa8c4, 0x14526b)
        case "foam": (0x9ccfd8, 0x1f5f69)
        case "iris": (0xc4a7e7, 0x57408a)
        default: (0xe0def4, 0x2a2540)
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
                           blue: CGFloat(hex & 0xff) / 255, alpha: 1)
        })
    }
}
