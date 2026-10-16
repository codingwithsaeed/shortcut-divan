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

struct Style {
    let font: CGFloat
    let spacing: CGFloat
    let maxRows: Int
    let columns: Int
    let rules: Bool
    var footer: Bool { columns == 1 && !rules } // small: no room for buttons beside the title

    init(_ family: WidgetFamily) {
        switch family {
        case .systemSmall: (font, spacing, maxRows, columns, rules) = (11, 5, 4, 1, false)
        case .systemMedium: (font, spacing, maxRows, columns, rules) = (12, 5, 4, 1, true)
        default: (font, spacing, maxRows, columns, rules) = (13, 6, 10, 1, true)
        }
    }
}

struct SectionView: View {
    let section: Section
    let style: Style
    let key: String
    let page: Int

    var body: some View {
        let accent = Color.rosePine(section.accent)
        let shown = Array(section.rows.dropFirst(current * style.maxRows).prefix(style.maxRows))
        let perColumn = Int((Double(style.maxRows) / Double(style.columns)).rounded(.up))

        VStack(alignment: .leading, spacing: style.spacing + 3) {
            HStack(spacing: 6) {
                Circle().fill(accent).frame(width: style.font * 0.6, height: style.font * 0.6)
                Text(verbatim: section.title)
                    .font(.system(size: style.font + 2, weight: .bold))
                    .lineLimit(1)
                Text(verbatim: section.rows.count.formatted())
                    .font(.system(size: style.font - 2, weight: .semibold).monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(accent.opacity(0.18), in: Capsule())
                    .foregroundStyle(accent)
                if !style.footer {
                    Spacer(minLength: 4)
                    controls
                }
            }
            .widgetAccentable()

            HStack(alignment: .top, spacing: 14) {
                ForEach(0..<style.columns, id: \.self) { column in
                    let rows = shown.dropFirst(column * perColumn).prefix(perColumn)
                    VStack(spacing: style.spacing) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                            if style.rules && index > 0 { Divider().opacity(0.5) }
                            RowView(row: row, accent: accent, size: style.font)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }

            if style.footer {
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    controls
                }
                .widgetAccentable()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var pages: Int { max(1, Int((Double(section.rows.count) / Double(style.maxRows)).rounded(.up))) }
    var current: Int { (page % pages + pages) % pages }

    // Page number, page up / down, next section.
    @ViewBuilder var controls: some View {
        if pages > 1 {
            Text(verbatim: "\((current + 1).formatted())/\(pages.formatted())")
                .font(.system(size: style.font - 1, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
            IconButton(symbol: "chevron.up", size: style.font, intent: TurnPage(key: key, delta: -1))
            IconButton(symbol: "chevron.down", size: style.font, intent: TurnPage(key: key, delta: 1))
        }
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
                .font(.system(size: size - 2, weight: .semibold))
                .frame(width: size + 10, height: size + 10)
                .background(.fill.tertiary, in: Circle())
                .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// What it does, then its keys as keycaps, as in the app.
struct RowView: View {
    let row: Shortcut
    let accent: Color
    let size: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: row.desc)
                .font(.system(size: size, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 4)
            Keycaps(keys: row.keys, accent: accent, size: size - 1)
                .widgetAccentable()
        }
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
        } else if family == .systemExtraLarge {
            HStack(alignment: .top, spacing: 28) {
                ForEach(entry.sections) { SectionView(section: $0, style: style, key: entry.key, page: entry.page) }
            }
        } else {
            SectionView(section: entry.sections[0], style: style, key: entry.key, page: entry.page)
        }
    }
}
