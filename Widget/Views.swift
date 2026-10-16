// How a section looks in each widget size.
import AppIntents
import SwiftUI
import WidgetKit

struct Entry: TimelineEntry {
    let date: Date
    let sections: [Section]
    let key: String // the widget's configuration, for its buttons
    let page: Int
}

// Sizes per widget family. Every row has the same height, so the number of rows that fit
// is worked out from the widget's real height instead of guessed (a guess too high pushed
// the header out of the top and cut the last row at the bottom).
struct Style {
    let font: CGFloat
    let rules: Bool
    var footer: Bool { !rules } // small: no room for buttons beside the title

    init(_ family: WidgetFamily) {
        switch family {
        case .systemSmall: (font, rules) = (11, false)
        case .systemMedium: (font, rules) = (12, true)
        default: (font, rules) = (13, true)
        }
    }

    var row: CGFloat { (font * 2.1).rounded() }
    var button: CGFloat { font + 10 }
    var gap: CGFloat { 6 }

    func rows(in height: CGFloat) -> Int {
        let room = height - button - gap - (footer ? button + gap : 0)
        return max(1, Int(room / row))
    }
}

struct SectionView: View {
    @Environment(\.widgetRenderingMode) var mode
    let section: Section
    let style: Style
    let perPage: Int
    let width: CGFloat
    let key: String
    let page: Int

    var body: some View {
        let accent = Color.rosePine(section.accent)
        let vibrant = mode != .fullColor // on the desktop behind windows: drawn in one tone
        let shown = Array(section.rows.dropFirst(current * perPage).prefix(perPage))

        VStack(alignment: .leading, spacing: style.gap) {
            HStack(spacing: 6) {
                Circle().fill(accent).frame(width: style.font * 0.6, height: style.font * 0.6)
                Text(verbatim: section.title)
                    .font(.app(style.font + 2, .bold))
                    .lineLimit(1)
                Text(verbatim: section.rows.count.formatted())
                    .font(.app(style.font - 2, .semibold).monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(accent.opacity(vibrant ? 0.12 : 0.18), in: Capsule())
                    .foregroundStyle(vibrant ? Color.primary : accent)
                if !style.footer {
                    Spacer(minLength: 4)
                    controls
                }
            }
            .frame(height: style.button)
            .widgetAccentable()

            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.offset) { index, row in
                    RowView(row: row, accent: accent, size: style.font, fill: vibrant ? 0.10 : 0.22, width: width)
                        .frame(height: style.row)
                        .overlay(alignment: .top) {
                            if style.rules && index > 0 { Divider().opacity(0.5) }
                        }
                }
            }

            if style.footer {
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    Spacer(minLength: 0)
                    controls
                }
                .frame(height: style.button)
                .widgetAccentable()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var pages: Int { max(1, Int((Double(section.rows.count) / Double(perPage)).rounded(.up))) }
    var current: Int { (page % pages + pages) % pages }

    // Page number and page up / down for a long section, then previous / next section.
    @ViewBuilder var controls: some View {
        if pages > 1 {
            Text(verbatim: "\((current + 1).formatted())/\(pages.formatted())")
                .font(.app(style.font - 1, .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize()
            IconButton(symbol: "chevron.up", size: style.font, intent: TurnPage(key: key, delta: -1))
            IconButton(symbol: "chevron.down", size: style.font, intent: TurnPage(key: key, delta: 1))
        }
        IconButton(symbol: "arrow.backward", size: style.font, intent: PreviousSection(key: key))
        IconButton(symbol: "arrow.forward", size: style.font, intent: NextSection(key: key))
    }
}

// A small tappable symbol in a section's header.
struct IconButton<Intent: AppIntent>: View {
    let symbol: String
    let size: CGFloat
    let intent: Intent

    var body: some View {
        Button(intent: intent) {
            Image(systemName: symbol)
                .font(.system(size: size - 0.5, weight: .semibold))
                .frame(width: size + 10, height: size + 10)
                .background(.fill.tertiary, in: Circle())
                .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// What it does, then its keys as keycaps, as in the app.
// Long keys never push the row past the widget's edge: the description keeps at least
// `share` of the width, and the keys step down until they fit in the rest: all of them,
// then only the first option of several ("⌘Z / ⇧⌘Z" shows ⌘Z), then smaller, then as text
// that shrinks to fit.
struct RowView: View {
    let row: Shortcut
    let accent: Color
    let size: CGFloat
    let fill: Double
    let width: CGFloat

    static let share = 0.4

    var body: some View {
        let first = row.keys.components(separatedBy: " / ").first ?? row.keys
        HStack(spacing: 8) {
            Text(verbatim: row.desc)
                .font(.app(size, .medium))
                .lineLimit(1)
                .frame(minWidth: width * Self.share, alignment: .leading)
            Spacer(minLength: 4)
            ViewThatFits(in: .horizontal) {
                Keycaps(keys: row.keys, accent: accent, size: size - 1, fill: fill)
                Keycaps(keys: first, accent: accent, size: size - 1, fill: fill)
                Keycaps(keys: first, accent: accent, size: size - 3, fill: fill)
                Text(verbatim: KeyText.spaced(first))
                    .font(.app(size - 1, .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .layoutPriority(1)
            .widgetAccentable()
        }
        .frame(width: width)
    }
}

struct DivanView: View {
    @Environment(\.widgetFamily) var family
    let entry: Entry

    var body: some View {
        SectionsContent(entry: entry, family: family)
            .environment(\.layoutDirection, .app)
            .environment(\.locale, Locale(identifier: AppLanguage.current))
            .containerBackground(for: .widget) {
                ZStack {
                    Rectangle().fill(.background)
                    LinearGradient(
                        colors: [Color.rosePine(entry.sections.first?.accent ?? "iris").opacity(0.16), .clear],
                        startPoint: .top, endPoint: .bottom)
                }
            }
            .widgetURL(link)
    }

    // A click outside the buttons opens the app on this section.
    var link: URL? {
        var parts = URLComponents()
        parts.scheme = "shortcutdivan"
        parts.host = "section"
        parts.path = "/" + (entry.sections.first?.title ?? "")
        return parts.url
    }
}

struct SectionsContent: View {
    let entry: Entry
    let family: WidgetFamily

    var body: some View {
        let style = Style(family)
        if entry.sections.isEmpty {
            Text("No shortcuts yet").foregroundStyle(.secondary)
        } else {
            GeometryReader { space in
                let perPage = style.rows(in: space.size.height)
                let shown = family == .systemExtraLarge ? entry.sections : [entry.sections[0]]
                let gap: CGFloat = 28
                let width = (space.size.width - gap * CGFloat(shown.count - 1)) / CGFloat(shown.count)
                HStack(alignment: .top, spacing: gap) {
                    ForEach(shown) {
                        SectionView(section: $0, style: style, perPage: perPage, width: width, key: entry.key, page: entry.page)
                    }
                }
            }
        }
    }
}
