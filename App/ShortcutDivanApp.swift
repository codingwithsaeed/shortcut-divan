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
                            Text("New Section").foregroundStyle(.secondary)
                        } icon: {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                                .frame(width: 24, height: 24)
                                .overlay(Image(systemName: "plus").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary))
                        }
                        .font(.system(size: 13, weight: .medium))
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Sections")
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { AppHeader(count: total) }
            .toolbar {
                ToolbarItemGroup {
                    ThemeButton()
                    LanguageMenu()
                    SettingsLink { Label("Settings", systemImage: "gearshape") }
                        .help("Settings")
                }
            }
            .environment(\.layoutDirection, .app)
            .navigationSplitViewColumnWidth(min: 240, ideal: 260)
        } detail: {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
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
                    .padding(24)
                    .environment(\.layoutDirection, .app)
                }
                .onChange(of: selected) { _, _ in
                    if let first = shown.first { proxy.scrollTo(store.sections[first.index].title, anchor: .top) }
                }
            }
        }
        .navigationTitle(selected == nil || selected == Self.all ? String(localized: "All Shortcuts") : selected ?? "")
        .searchable(text: $query, placement: .toolbar, prompt: Text("Search shortcuts"))
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
        .onExitCommand { NSApp.keyWindow?.close() }
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

// A section as a card: title bar, column headers, then one row per shortcut with rules between.
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
                Circle().fill(accent).frame(width: 9, height: 9)
                Text(verbatim: section.title)
                    .font(.system(size: 15, weight: .bold))
                Text(verbatim: rows.count.formatted())
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(accent.opacity(0.15), in: Capsule())
                    .foregroundStyle(accent)
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
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(accent.opacity(0.12))

            if rows.isEmpty {
                Text("No shortcuts yet.")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(16)
            } else {
                HStack(spacing: 16) {
                    Text("Keys").frame(width: RowLine.keysWidth, alignment: .leading)
                    Text("Description")
                    Spacer(minLength: 0)
                }
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                Divider()
                ForEach(Array(rows.enumerated()), id: \.element) { position, row in
                    if position > 0 { Divider().padding(.horizontal, 16) }
                    RowLine(
                        shortcut: section.rows[row], accent: accent,
                        edit: { edit(.row(section: index, row: row)) },
                        delete: { delete(.row(section: index, row: row)) }
                    )
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
    }
}

// One shortcut. Edit by double-click, the pencil, or right-click.
struct RowLine: View {
    static let keysWidth: CGFloat = 190

    let shortcut: Shortcut
    let accent: Color
    let edit: () -> Void
    let delete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 16) {
            Text(verbatim: KeyText.spaced(shortcut.keys))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent)
                .environment(\.layoutDirection, .leftToRight) // keys read left to right, in Persian too
                .frame(width: Self.keysWidth, alignment: .leading)
            Text(verbatim: shortcut.desc)
                .font(.system(size: 14))
                .lineLimit(1)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Button("Edit", systemImage: "pencil", action: edit)
                Button("Delete", systemImage: "trash", action: delete)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(hovering ? AnyShapeStyle(.quaternary.opacity(0.4)) : AnyShapeStyle(.clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: edit)
        .contextMenu {
            Button("Edit…", action: edit)
            Button("Delete", role: .destructive, action: delete)
        }
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

// Top of the sidebar: the app's icon, name, and how many shortcuts it holds.
struct AppHeader: View {
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Shortcut Divan").font(.system(size: 15, weight: .semibold))
                Text("\(count) shortcuts").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 12)
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
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.rosePine(accent).gradient)
                .frame(width: 24, height: 24)
                .overlay(Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(.white))
        }
        .font(.system(size: 13, weight: .medium))
        .badge(count)
        .padding(.vertical, 3)
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
