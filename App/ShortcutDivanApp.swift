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
                SidebarRow(title: "All Shortcuts", symbol: "square.stack", count: total)
                    .tag(Self.all)
                SwiftUI.Section {
                    ForEach(Array(store.sections.enumerated()), id: \.offset) { index, section in
                        SidebarRow(
                            title: LocalizedStringKey(section.title), verbatim: section.title,
                            accent: section.accent, count: section.rows.filter { $0.only == nil }.count
                        )
                        .tag(section.title)
                        .contextMenu { sectionMenu(index) }
                    }
                    Button { editing = .section(nil) } label: {
                        Label {
                            Text("New Section")
                        } icon: {
                            Image(systemName: "plus").frame(width: 16).foregroundStyle(.secondary)
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
                        HStack(spacing: 12) {
                            SearchField(text: $query, focus: $searching)
                            GlassGroup {
                                ThemeButton(size: SearchField.height)
                                LanguageMenu(size: SearchField.height)
                                SettingsLink { GlassIcon(symbol: "gearshape", size: SearchField.height) }
                                    .glassDisc()
                                    .help("Settings")
                            }
                            .focusable(false)
                        }
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
            .background(Backdrop())
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
                    Button { edit(.row(section: index, row: nil)) } label: { GlassIcon(symbol: "plus", size: 32) }
                        .glassDisc()
                        .focusable(false)
                        .help("Add a shortcut to this section")
                    SwiftUI.Menu { menu() } label: { GlassIcon(symbol: "ellipsis", size: 32) }
                        .glassDisc()
                        .focusable(false)
                        .help("More")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(accent.opacity(0.12))

            if rows.isEmpty {
                Text("No shortcuts yet.")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(18)
            } else {
                HStack {
                    Text("Description")
                    Spacer(minLength: 0)
                    Text("Keys")
                }
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                Divider()
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element) { position, row in
                        if position > 0 { Divider().opacity(0.5).padding(.horizontal, 14) }
                        RowLine(
                            shortcut: section.rows[row], accent: accent,
                            edit: { edit(.row(section: index, row: row)) },
                            delete: { delete(.row(section: index, row: row)) }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .glassCard(cornerRadius: 16)
    }
}

// One shortcut: what it does, then its keys as keycaps. Edit by double-click, hover buttons, or right-click.
struct RowLine: View {
    let shortcut: Shortcut
    let accent: Color
    let edit: () -> Void
    let delete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: shortcut.desc)
                .font(.system(size: 13.5))
                .lineLimit(1)
            Spacer(minLength: 12)
            RowActions(edit: edit, delete: delete)
                .opacity(hovering ? 1 : 0)
            Keycaps(keys: shortcut.keys, accent: accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovering ? accent.opacity(0.10) : .clear)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
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

// Edit and delete, shown on hover: small rounded squares in the keycaps' shape, so the row
// reads as one set of tiles; the bin is tinted red.
struct RowActions: View {
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: edit) { tile("pencil", tint: .primary) }
                .help("Edit")
            Button(action: delete) { tile("trash", tint: .red) }
                .help("Delete")
        }
        .buttonStyle(.plain)
        .focusable(false)
        .fixedSize()
    }

    func tile(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 26, height: 22)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(tint.opacity(0.25), lineWidth: 0.5))
            .contentShape(Rectangle())
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

// Every sidebar row: a section's color dot (or a symbol), the name, and a count.
struct SidebarRow: View {
    var title: LocalizedStringKey
    var verbatim: String?
    var symbol: String?
    var accent = "iris"
    let count: Int

    var body: some View {
        Label {
            if let verbatim { Text(verbatim: verbatim) } else { Text(title) }
        } icon: {
            if let symbol {
                Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 16)
            } else {
                Circle().fill(Color.rosePine(accent)).frame(width: 9, height: 9).frame(width: 16)
            }
        }
        .badge(count)
    }
}

// A wide search field at the top of the list, as in launcher apps. ⌘F focuses it, ⎋ clears it.
struct SearchField: View {
    static let height: CGFloat = 42

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
        .frame(height: Self.height)
        .glassCard(cornerRadius: Self.height / 2)
    }
}

// Cycles automatic → light → dark.
struct ThemeButton: View {
    let size: CGFloat
    @State private var theme = Theme.current

    var body: some View {
        Button {
            theme = theme.next
            theme.apply()
        } label: {
            GlassIcon(symbol: theme.symbol, size: size)
                .contentTransition(.symbolEffect(.replace))
        }
        .glassDisc()
        .help(theme.name)
    }
}

struct LanguageMenu: View {
    let size: CGFloat

    var body: some View {
        Menu {
            Picker("Language", selection: Binding { AppLanguage.chosen ?? "" } set: { LanguageSwitch.to($0) }) {
                Text("System").tag("")
                Text(verbatim: "English").tag("en")
                Text(verbatim: "فارسی").tag("fa")
            }
            .pickerStyle(.inline)
        } label: {
            GlassIcon(symbol: "globe", size: size)
        }
        .glassDisc()
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

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension View {
    // No title in the toolbar: the search field and the cards say where you are.
    @ViewBuilder func hidingTitle() -> some View {
        if #available(macOS 15, *) { toolbar(removing: .title) } else { self }
    }
}

// Liquid Glass on macOS 26; a frosted material before that.
extension View {
    @ViewBuilder func glassCard(cornerRadius: CGFloat) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.separator))
        }
    }
}

// Soft Rosé Pine color behind the cards, so the glass has something to show.
struct Backdrop: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.background)
            Circle().fill(Color.rosePine("iris").opacity(0.45)).frame(width: 560).blur(radius: 120)
                .offset(x: -220, y: -200)
            Circle().fill(Color.rosePine("love").opacity(0.35)).frame(width: 500).blur(radius: 120)
                .offset(x: 260, y: 60)
            Circle().fill(Color.rosePine("foam").opacity(0.35)).frame(width: 460).blur(radius: 120)
                .offset(x: -60, y: 320)
        }
        .ignoresSafeArea()
    }
}

// A round icon button's face: the symbol centered in a circle of the given size, all of it clickable.
struct GlassIcon: View {
    let symbol: String
    let size: CGFloat

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.4, weight: .medium))
            .frame(width: size, height: size)
            .contentShape(Circle())
    }
}

extension View {
    // The same round glass for buttons and menus alike (menus ignore button styles otherwise).
    @ViewBuilder func glassDisc() -> some View {
        let plain = buttonStyle(.plain).menuStyle(.button).menuIndicator(.hidden).fixedSize()
        if #available(macOS 26, *) {
            plain.glassEffect(.regular.interactive(), in: .circle)
        } else {
            plain.background(.regularMaterial, in: Circle()).overlay(Circle().strokeBorder(.separator))
        }
    }
}
