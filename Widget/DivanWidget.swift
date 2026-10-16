// Desktop widget: one section of your shortcuts (two in extra large), picked when the
// widget is added or edited.
import AppIntents
import SwiftUI
import WidgetKit

// MARK: configuration

// The section titles. Plain strings rather than an AppEntity:
// the system failed to resolve a custom entity type in this extension, so a picked
// section always arrived as nil.
struct SectionOptions: DynamicOptionsProvider {
    func results() async throws -> [String] {
        Shortcuts.load().map(\.title)
    }
}

struct SelectSection: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Shortcut Divan"
    static let description = IntentDescription("Pick the section to show.")

    @Parameter(title: "Section", optionsProvider: SectionOptions())
    var section: String?

    @Parameter(title: "Second section", optionsProvider: SectionOptions())
    var second: String?

    // Only extra large shows two sections, so only it asks for the second.
    static var parameterSummary: some ParameterSummary {
        When(widgetFamily: .equalTo, .systemExtraLarge) {
            Summary {
                \.$section
                \.$second
            }
        } otherwise: {
            Summary {
                \.$section
            }
        }
    }
}

// MARK: timeline

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: .now, sections: Array(Shortcuts.load().prefix(2)), key: "", page: 0)
    }

    func snapshot(for configuration: SelectSection, in context: Context) async -> Entry {
        entry(for: configuration)
    }

    // The app reloads the widgets whenever it saves; re-read every 15 minutes anyway.
    func timeline(for configuration: SelectSection, in context: Context) async -> Timeline<Entry> {
        Timeline(entries: [entry(for: configuration)], policy: .after(.now.addingTimeInterval(15 * 60)))
    }

    // The chosen section, then the second one (or the next in the file), moved on by
    // however many times the widget's next-section button was pressed.
    func entry(for configuration: SelectSection) -> Entry {
        let all = Shortcuts.load()
        let key = "\(configuration.section ?? "")|\(configuration.second ?? "")"
        let position = Positions.get(key)
        guard !all.isEmpty else { return Entry(date: .now, sections: [], key: key, page: 0) }
        let first = all.firstIndex { $0.title == configuration.section } ?? 0
        let second = all.firstIndex { $0.title == configuration.second } ?? first + 1
        let a = (first + position.shift) % all.count, b = (second + position.shift) % all.count
        let picked = a == b ? [a] : [a, b]
        return Entry(date: .now, sections: picked.map { all[$0] }, key: key, page: position.page)
    }
}

@main
struct DivanWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ShortcutDivan", intent: SelectSection.self, provider: Provider()) {
            DivanView(entry: $0)
        }
        .configurationDisplayName("Shortcut Divan")
        .description("Your keyboard shortcuts on the desktop.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}
