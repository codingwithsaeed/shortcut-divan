// Shortcut Divan: your keyboard shortcuts in a desktop widget, and this window to browse,
// search and edit them. A click on the widget opens the window on that widget's section.
// `open -g -a "Shortcut Divan" --args --reload` only refreshes the widgets and quits.
import SwiftUI
import WidgetKit

@main
enum Main {
    static func main() {
        // In Persian the whole window, sidebar and title bar included, goes right to left,
        // even when the rest of the system is in English. AppKit reads this at launch.
        UserDefaults.standard.set(LayoutDirection.app == .rightToLeft, forKey: "AppleTextDirection")
        ShortcutDivanApp.main()
    }
}

struct ShortcutDivanApp: App {
    @NSApplicationDelegateAdaptor var delegate: AppDelegate
    private let store = Store.shared

    init() {
        if CommandLine.arguments.contains("--reload") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSApp.terminate(nil) }
        }
    }

    var body: some Scene {
        Window("Shortcut Divan", id: "main") {
            DivanWindow()
        }
        .defaultSize(width: 860, height: 600)

        Settings {
            SettingsView()
        }
        .commands {
            CommandGroup(replacing: .importExport) {
                Button("Import…") { store.importFile() }
                Button("Export…") { store.exportFile() }
                Divider()
                Button("Follow a Shortcuts File…") { store.link() }
                Button("Stop Following File") { store.unlink() }
                    .disabled(store.linkedFile == nil)
                Divider()
                Button("Restore Default Shortcuts…") { store.restoreDefaults() }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// What the edit sheet is open for: a row (nil row = new) or a section (nil = new).
enum Editing: Identifiable {
    case row(section: Int, row: Int?)
    case section(Int?)

    var id: String {
        switch self {
        case let .row(section, row): "row \(section) \(row ?? -1)"
        case let .section(section): "section \(section ?? -1)"
        }
    }
}

struct DivanWindow: View {
    @Bindable private var store = Store.shared
    @State private var selected: String? = Self.all
    @State private var query = ""

    static let all = "\u{0}all"

    var total: Int { store.sections.reduce(0) { $0 + $1.rows.filter { $0.only == nil }.count } }
    @State private var editing: Editing?
    @State private var deleting: Editing?

    @FocusState private var searching: Bool

    var body: some View {
        NavigationSplitView {
            List(selection: $selected) {
                SidebarRow(title: "All Shortcuts", symbol: "square.grid.2x2.fill", accent: "iris", count: total)
                    .tag(Self.all)
                SwiftUI.Section {
                    ForEach(Array(store.sections.enumerated()), id: \.offset) { index, section in
                        SidebarRow(
                            title: LocalizedStringKey(section.title), verbatim: section.title, symbol: "command",
                            accent: section.accent, count: section.rows.filter { $0.only == nil }.count
                        )
                        .tag(section.title)
                        .contextMenu { sectionMenu(index) }
                    }
                    Button { editing = .section(nil) } label: {
                        Label {
                            Text("New Section")
                        } icon: {
                            Image(systemName: "plus").frame(width: 20).foregroundStyle(.secondary)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Sections")
                }
            }
            .environment(\.layoutDirection, .app)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        SearchField(text: $query, focus: $searching)
                        ForEach(shown, id: \.index) { item in
                            SectionTable(
                                section: store.sections[item.index], index: item.index, rows: item.rows,
                                edit: { editing = $0 }, delete: { deleting = $0 },
                                menu: { sectionMenu(item.index) }
                            )
                            .id(store.sections[item.index].title)
                        }
                        if shown.isEmpty && !query.isEmpty {
                            Text("Nothing matches “\(query)”.").foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
                    .padding(.top, 6)
                    .environment(\.layoutDirection, .app)
                }
                .onChange(of: selected) { _, _ in
                    if let first = shown.first { proxy.scrollTo(store.sections[first.index].title, anchor: .top) }
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    ControlGroup {
                        ThemeButton()
                        LanguageMenu()
                        SettingsLink { Label("Settings", systemImage: "gearshape") }
                            .help("Settings")
                    }
                }
            }
        }
        .navigationTitle("Shortcut Divan")
        .hidingTitle()
        .background {
            Button("") { searching = true }.keyboardShortcut("f").hidden()
        }
        .sheet(item: $editing) { editing in
            Group {
                switch editing {
                case let .row(section, row):
                    RowEditor(
                        sections: store.sections.map(\.title), section: section,
                        row: row.map { store.sections[section].rows[$0] } ?? Shortcut(keys: "", desc: "")
                    ) { saved, target in
                        if let row, target == section {
                            store.sections[section].rows[row] = saved
                        } else {
                            if let row { store.sections[section].rows.remove(at: row) }
                            store.sections[target].rows.append(saved)
                        }
                        store.commit()
                    }
                case let .section(index):
                    SectionEditor(section: index.map { store.sections[$0] } ?? Section(title: "", accent: "iris", rows: [])) { saved in
                        if let index { store.sections[index] = saved } else { store.sections.append(saved) }
                        selected = saved.title
                        store.commit()
                    }
                }
            }
            .environment(\.layoutDirection, .app)
        }
        .confirmationDialog(deleteTitle, isPresented: Binding { deleting != nil } set: { if !$0 { deleting = nil } }) {
            Button("Delete", role: .destructive) {
                switch deleting {
                case let .row(section, row?): store.sections[section].rows.remove(at: row)
                case let .section(index?): store.sections.remove(at: index)
                default: break
                }
                store.commit()
            }
        }
        .alert("Something went wrong", isPresented: Binding { store.error != nil } set: { if !$0 { store.error = nil } }) {
        } message: {
            Text(verbatim: store.error ?? "")
        }
        // shortcutdivan://section/<title>, from a click on the widget.
        .onOpenURL { url in
            store.reload()
            query = ""
            selected = url.pathComponents.dropFirst().first
        }
        .onExitCommand { if query.isEmpty { NSApp.keyWindow?.close() } else { query = "" } }
        .onAppear { Theme.current.apply() }
        .frame(minWidth: 680, minHeight: 480)
    }

    @ViewBuilder func sectionMenu(_ index: Int) -> some View {
        Button("Add Shortcut…") { editing = .row(section: index, row: nil) }
        Button("Edit Section…") { editing = .section(index) }
        Divider()
        Button("Delete Section…", role: .destructive) { deleting = .section(index) }
    }

    var deleteTitle: String {
        switch deleting {
        case let .row(section, row?):
            String(localized: "Delete “\(store.sections[section].rows[row].keys)”?")
        case let .section(index?):
            String(localized: "Delete the “\(store.sections[index].title)” section and its \(store.sections[index].rows.count) shortcuts?")
        default: ""
        }
    }

    // The sections and the indices of the rows to show: all of them, or the search matches.
    var shown: [(index: Int, rows: [Int])] {
        let words = query.lowercased().split(separator: " ")
        return store.sections.enumerated().compactMap { index, section in
            let rows = section.rows.indices.filter { row in
                let shortcut = section.rows[row]
                let text = "\(section.title) \(shortcut.keys) \(shortcut.desc)".lowercased()
                return shortcut.only == nil && words.allSatisfy { text.contains($0) }
            }
            guard words.isEmpty || !rows.isEmpty else { return nil }
            // A picked section shows alone, unless searching (search looks everywhere).
            guard !words.isEmpty || selected == nil || selected == Self.all || selected == section.title else { return nil }
            return (index, rows)
        }
    }
}

// A section as a card: a header with its name and actions, then one row per shortcut.
struct SectionTable<Menu: View>: View {
    let section: Section
    let index: Int
    let rows: [Int]
    let edit: (Editing) -> Void
    let delete: (Editing) -> Void
    @ViewBuilder let menu: () -> Menu

    var body: some View {
        let accent = Color.rosePine(section.accent)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(accent).frame(width: 4, height: 16)
                Text(verbatim: section.title)
                    .font(.system(size: 14, weight: .semibold))
                Text(verbatim: rows.count.formatted())
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                GlassGroup {
                    Button("Add Shortcut", systemImage: "plus") { edit(.row(section: index, row: nil)) }
                        .labelStyle(.iconOnly)
                        .glassCircle()
                        .focusable(false)
                        .help("Add a shortcut to this section")
                    SwiftUI.Menu { menu() } label: { Label("More", systemImage: "ellipsis") }
                        .labelStyle(.iconOnly)
                        .menuIndicator(.hidden)
                        .glassCircle()
                        .focusable(false)
                        .fixedSize()
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .padding(.vertical, 8)

            Divider()

            if rows.isEmpty {
                Text("No shortcuts yet.")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(18)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element) { position, row in
                        if position > 0 { Divider().opacity(0.5).padding(.horizontal, 14) }
                        RowLine(
                            shortcut: section.rows[row],
                            edit: { edit(.row(section: index, row: row)) },
                            delete: { delete(.row(section: index, row: row)) }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator.opacity(0.6)))
    }
}

// One shortcut: what it does, then its keys as keycaps. Edit by double-click, hover buttons, or right-click.
struct RowLine: View {
    let shortcut: Shortcut
    let edit: () -> Void
    let delete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: shortcut.desc)
                .font(.system(size: 13.5))
                .lineLimit(1)
            Spacer(minLength: 12)
            HStack(spacing: 2) {
                Button("Edit", systemImage: "pencil", action: edit)
                Button("Delete", systemImage: "trash", action: delete)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .opacity(hovering ? 1 : 0)
            Keycaps(keys: shortcut.keys)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovering ? AnyShapeStyle(.quaternary.opacity(0.5)) : AnyShapeStyle(.clear))
                .padding(.horizontal, 4)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: edit)
        .contextMenu {
            Button("Edit…", action: edit)
            Button("Delete", role: .destructive, action: delete)
        }
    }
}

// "⇧⌘Z / ⌘Z" as ⇧ ⌘ Z keycaps, a slash, and ⌘ Z keycaps. Typed commands ("cd -") stay one cap.
struct Keycaps: View {
    let keys: String

    enum Part: Hashable { case cap(String), gap, text(String) }

    static let symbols: Set<Character> = ["⌃", "⌥", "⇧", "⌘", "⇥", "↩", "⎋", "⌫", "␣", "←", "→", "↑", "↓"]

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
        HStack(spacing: 4) {
            ForEach(Array(Self.parts(keys).enumerated()), id: \.offset) { _, part in
                switch part {
                case let .cap(text):
                    Text(verbatim: text)
                        .font(.system(size: 12, weight: .medium, design: text.count > 1 && !text.contains(where: Self.symbols.contains) && text != "Space" ? .monospaced : .default))
                        .frame(minWidth: 14)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(.separator.opacity(0.8), lineWidth: 0.5)
                        )
                case .gap:
                    Color.clear.frame(width: 4, height: 1)
                case let .text(text):
                    Text(verbatim: text).font(.system(size: 12)).foregroundStyle(.tertiary)
                }
            }
        }
        .foregroundStyle(.primary.opacity(0.85))
        .environment(\.layoutDirection, .leftToRight) // keys read left to right, in Persian too
        .fixedSize()
    }
}

struct RowEditor: View {
    let sections: [String]
    @State var section: Int
    @State var row: Shortcut
    let save: (Shortcut, Int) -> Void
    @Environment(\.dismiss) private var dismiss

    init(sections: [String], section: Int, row: Shortcut, save: @escaping (Shortcut, Int) -> Void) {
        self.sections = sections
        _section = State(initialValue: section)
        _row = State(initialValue: row)
        self.save = save
    }

    static let symbols = ["⌃", "⌥", "⇧", "⌘", "⇥", "↩", "⎋", "⌫", "␣", "←", "→", "↑", "↓"]

    var body: some View {
        Form {
            TextField("Keys", text: $row.keys, prompt: Text(verbatim: "⇧⌘D"))
                .environment(\.layoutDirection, .leftToRight)
            HStack(spacing: 4) {
                ForEach(Self.symbols, id: \.self) { symbol in
                    Button { row.keys += symbol } label: { Text(verbatim: symbol) }
                        .font(.system(size: 14))
                }
            }
            .environment(\.layoutDirection, .leftToRight)
            TextField("Description", text: $row.desc, prompt: Text("split horizontally"))
            Picker("Section", selection: $section) {
                ForEach(Array(sections.enumerated()), id: \.offset) { Text(verbatim: $1).tag($0) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save(Shortcut(keys: row.keys.trimmed, desc: row.desc.trimmed, only: row.only), section)
                    dismiss()
                }
                .disabled(row.keys.trimmed.isEmpty || row.desc.trimmed.isEmpty)
            }
        }
    }
}

struct SectionEditor: View {
    @State var section: Section
    let save: (Section) -> Void
    @Environment(\.dismiss) private var dismiss

    static let colorNames: [String: LocalizedStringKey] = [
        "love": "Pink", "gold": "Gold", "rose": "Rose", "pine": "Blue", "foam": "Teal", "iris": "Purple",
    ]

    var body: some View {
        Form {
            TextField("Title", text: $section.title)
            Picker("Color", selection: $section.accent) {
                ForEach(Shortcuts.accents, id: \.self) { name in
                    Label {
                        Text(Self.colorNames[name] ?? "")
                    } icon: {
                        Image(systemName: "circle.fill").foregroundStyle(Color.rosePine(name))
                    }
                    .tag(name)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    section.title = section.title.trimmed
                    save(section)
                    dismiss()
                }
                .disabled(section.title.trimmed.isEmpty)
            }
        }
    }
}

// Light, dark or following the system; applied to the whole app.
enum Theme: String, CaseIterable {
    case system, light, dark

    static var current: Theme { Theme(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .system }

    var next: Theme { self == .system ? .light : self == .light ? .dark : .system }
    var symbol: String { self == .system ? "circle.lefthalf.filled" : self == .light ? "sun.max.fill" : "moon.fill" }
    var name: LocalizedStringKey { self == .system ? "Automatic" : self == .light ? "Light" : "Dark" }

    func apply() {
        UserDefaults.standard.set(rawValue, forKey: "theme")
        NSApp?.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

// Every sidebar row: a colored tile with a white symbol, the name, and a count.
struct SidebarRow: View {
    var title: LocalizedStringKey
    var verbatim: String?
    let symbol: String
    let accent: String
    let count: Int

    var body: some View {
        Label {
            if let verbatim { Text(verbatim: verbatim) } else { Text(title) }
        } icon: {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.rosePine(accent).gradient)
                .frame(width: 20, height: 20)
                .overlay(Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(.white))
        }
        .badge(count)
    }
}

// A wide search field at the top of the list, as in launcher apps. ⌘F focuses it, ⎋ clears it.
struct SearchField: View {
    @Binding var text: String
    var focus: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search shortcuts", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused(focus)
            if text.isEmpty {
                Text(verbatim: "⌘F")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .environment(\.layoutDirection, .leftToRight)
            } else {
                Button("Clear", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(focus.wrappedValue ? AnyShapeStyle(Color.accentColor.opacity(0.6)) : AnyShapeStyle(.separator.opacity(0.6)))
        )
    }
}

// Cycles automatic → light → dark.
struct ThemeButton: View {
    @State private var theme = Theme.current

    var body: some View {
        Button {
            theme = theme.next
            theme.apply()
        } label: {
            Label("Theme", systemImage: theme.symbol)
                .contentTransition(.symbolEffect(.replace))
        }
        .help(theme.name)
    }
}

struct LanguageMenu: View {
    var body: some View {
        Menu {
            Picker("Language", selection: Binding { AppLanguage.chosen ?? "" } set: { LanguageSwitch.to($0) }) {
                Text("System").tag("")
                Text(verbatim: "English").tag("en")
                Text(verbatim: "فارسی").tag("fa")
            }
            .pickerStyle(.inline)
        } label: {
            Label("Language", systemImage: "globe")
        }
        .fixedSize()
        .help("Language")
    }
}

// ⌘, : appearance, language, and where the shortcuts live.
struct SettingsView: View {
    @Bindable private var store = Store.shared
    @State private var theme = Theme.current
    @State private var language = AppLanguage.chosen ?? ""

    var body: some View {
        Form {
            SwiftUI.Section {
                Picker("Appearance", selection: $theme) {
                    Label("Automatic", systemImage: "circle.lefthalf.filled").tag(Theme.system)
                    Label("Light", systemImage: "sun.max.fill").tag(Theme.light)
                    Label("Dark", systemImage: "moon.fill").tag(Theme.dark)
                }
                .onChange(of: theme) { _, theme in theme.apply() }
                Picker("Language", selection: $language) {
                    Text("System").tag("")
                    Text(verbatim: "English").tag("en")
                    Text(verbatim: "فارسی").tag("fa")
                }
                .onChange(of: language) { _, language in LanguageSwitch.to(language) }
            }
            SwiftUI.Section {
                LabeledContent("Shortcuts File") {
                    if let file = store.linkedFile {
                        Text(verbatim: file.path).truncationMode(.middle).lineLimit(1).help(file.path)
                    } else {
                        Text("Kept by the app")
                    }
                }
                HStack {
                    Button("Follow a Shortcuts File…") { store.link() }
                    if store.linkedFile != nil { Button("Stop Following File") { store.unlink() } }
                }
            } footer: {
                Text("A followed file is read, watched for changes, and saved back to when you edit here.")
                    .foregroundStyle(.secondary)
            }
            SwiftUI.Section {
                HStack {
                    Button("Import…") { store.importFile() }
                    Button("Export…") { store.exportFile() }
                    Spacer()
                    Button("Restore Default Shortcuts…", role: .destructive) { store.restoreDefaults() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.layoutDirection, .app)
    }
}

// Switching language restarts the app, so every text and the layout direction change together.
enum LanguageSwitch {
    static func to(_ language: String) {
        guard language != (AppLanguage.chosen ?? "") else { return }
        let defaults = UserDefaults.standard
        if language.isEmpty {
            defaults.removeObject(forKey: "AppleLanguages")
            try? FileManager.default.removeItem(at: AppLanguage.file)
        } else {
            defaults.set([language], forKey: "AppleLanguages")
            try? FileManager.default.createDirectory(at: AppLanguage.file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(language.utf8).write(to: AppLanguage.file)
        }
        defaults.synchronize()
        WidgetCenter.shared.reloadAllTimelines()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

// Round glass buttons that merge when close (macOS 26); plain borderless ones before.
struct GlassGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: 8) { HStack(spacing: 8, content: content) }
        } else {
            HStack(spacing: 8, content: content)
        }
    }
}

extension View {
    @ViewBuilder func glassCircle() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.large)
        } else {
            buttonStyle(.borderless)
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension View {
    // No title in the toolbar: the search field and the cards say where you are.
    @ViewBuilder func hidingTitle() -> some View {
        if #available(macOS 15, *) { toolbar(removing: .title) } else { self }
    }
}
