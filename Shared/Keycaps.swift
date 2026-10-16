// Shortcut keys drawn as keycaps, in the app and the widget.
import SwiftUI

// "⇧⌘Z / ⌘Z" as ⇧ ⌘ Z keycaps, a slash, and ⌘ Z keycaps. Typed commands ("cd -") stay one cap.
struct Keycaps: View {
    let keys: String
    var accent: Color = .primary
    var size: CGFloat = 12.5
    var fill = 0.22 // lighter in the widget's one-tone desktop look, so the keys stay readable

    enum Part: Hashable { case cap(String), gap, text(String) }

    static let symbols: Set<Character> = ["⌃", "⌥", "⇧", "⌘", "⇥", "↩", "⎋", "⌫", "␣", "←", "→", "↑", "↓"]

    // A typed command ("cd -", "tinker") rather than a key: shown in a monospaced font.
    static func isCommand(_ text: String) -> Bool {
        text.count > 1 && !text.contains(where: symbols.contains) && text != "Space"
    }

    static func parts(_ keys: String) -> [Part] {
        var parts: [Part] = []
        for (n, option) in keys.components(separatedBy: " / ").enumerated() {
            if n > 0 { parts.append(.text("/")) }
            guard option.contains(where: symbols.contains) else {
                parts.append(.cap(option))
                continue
            }
            for (w, word) in option.split(separator: " ").enumerated() {
                if w > 0 { parts.append(.gap) }
                var run = ""
                for char in word {
                    if symbols.contains(char) {
                        if !run.isEmpty { parts.append(.cap(run)); run = "" }
                        parts.append(.cap(char == "␣" ? "Space" : String(char)))
                    } else {
                        run.append(char)
                    }
                }
                if !run.isEmpty { parts.append(.cap(run)) }
            }
        }
        return parts
    }

    var body: some View {
        HStack(spacing: size * 0.32) {
            ForEach(Array(Self.parts(keys).enumerated()), id: \.offset) { _, part in
                switch part {
                case let .cap(text):
                    Text(verbatim: text)
                        .font(Self.isCommand(text) ? .system(size: size, weight: .semibold, design: .monospaced) : .app(size, .semibold))
                        .frame(minWidth: size + 1.5)
                        .padding(.horizontal, size * 0.48)
                        .padding(.vertical, size * 0.24)
                        .background(accent.opacity(fill), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(accent.opacity(fill * 2), lineWidth: 0.5)
                        )
                case .gap:
                    Color.clear.frame(width: 4, height: 1)
                case let .text(text):
                    Text(verbatim: text).font(.app(size)).foregroundStyle(.tertiary)
                }
            }
        }
        .foregroundStyle(.primary)
        .environment(\.layoutDirection, .leftToRight) // keys read left to right, in Persian too
        .fixedSize()
    }
}
