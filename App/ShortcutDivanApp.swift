// Shortcut Divan: your keyboard shortcuts in a desktop widget, and this window to browse,
// search and edit them. A click on the widget opens the window on that widget's section.
// `open -g -a "Shortcut Divan" --args --reload` only refreshes the widgets and quits.
import SwiftUI
import UniformTypeIdentifiers
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
        // No title bar: the search bar sits where it would be, and stays there as the
        // sections scroll under it.
        .windowStyle(.hiddenTitleBar)

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
    @State private var sidebarShown = true
    @AppStorage("sidebarWidth") private var sidebarWidth: Double = 310
    // The sidebar column, kept in range even if an older, narrower width was saved.
    var sideWidth: CGFloat { min(max(sidebarWidth, SidebarResizer.range.lowerBound), SidebarResizer.range.upperBound) }
    @State private var columnWidth: CGFloat = 0
    @State private var contentWidth: CGFloat = 0

    // The layout. The sidebar is a card inset from the window, holding the window buttons at
    // its top corner (moved down from the window's edge), the app's name, and a card per
    // section. Beside it, one header row level with the window buttons; then the search
    // field, pinned, and level with the sidebar's first row; then the cards, which scroll
    // under both.
    static let headerHeight: CGFloat = 60
    static let inset: CGFloat = 8 // the sidebar card from the window's edges
    static let sidebarRadius: CGFloat = 18
    static let disc: CGFloat = 34 // the round buttons in the header row
    static let smallDisc: CGFloat = 30 // in the sidebar card's top, where room is tight
    static let barHeight = headerHeight + SearchField.height + 10 // the pinned part of the content
    static let cardsTop = barHeight + 8
    static let side: CGFloat = 28 // the content's side margin, shared by the header, search and cards
    static let listInset: CGFloat = 10 // the sidebar rows' margin from the card's sides

    var body: some View {
        // One backdrop under the whole window, so the sidebar and the cards sit on the same
        // colors; a line with a soft shadow is all that parts them.
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                if sidebarShown {
                    sidebarColumn
                    Color.clear.frame(width: 1)
                }
                contentColumn
            }
            fadeLayer
            if sidebarShown { sidebarEdge }
            pinnedRows
        }
        .background(TrafficLights(centerY: Self.headerHeight / 2))
        .environment(\.layoutDirection, .app)
        .font(.app(13))
        .ignoresSafeArea(.container, edges: .top)
        .background(Backdrop())
        .navigationTitle("Shortcut Divan")
        .hidingTitle()
        .clearToolbar()
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

    var sidebarColumn: some View {
        VStack(spacing: 0) {
            sidebarHeader
            ScrollView {
                SidebarList(
                    sections: store.sections, total: total, selected: $selected,
                    menu: { sectionMenu($0) }
                ) { from, to in
                    withAnimation(.snappy) {
                        store.sections.move(fromOffsets: [from], toOffset: to > from ? to + 1 : to)
                    }
                    store.commit()
                }
                .padding(.horizontal, Self.listInset)
                .padding(.bottom, Self.listInset)
            }
            .scrollIndicators(.never)
        }
        .frame(width: sideWidth - Self.inset)
        .clipShape(RoundedRectangle(cornerRadius: Self.sidebarRadius, style: .continuous))
        .glassCard(cornerRadius: Self.sidebarRadius)
        .padding([.leading, .vertical], Self.inset)
        .transition(.move(edge: .leading).combined(with: .opacity))
    }

    var contentColumn: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
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
                .padding(.horizontal, Self.side)
                .padding(.bottom, Self.side)
                .padding(.top, Self.cardsTop - Self.barHeight)
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
                .environment(\.layoutDirection, .app)
            }
            .safeAreaPadding(.top, Self.barHeight)
            .noTopEdgeEffect()
            .onChange(of: selected) { _, _ in
                if let first = shown.first { proxy.scrollTo(store.sections[first.index].title, anchor: .top) }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { columnWidth = $0 }
    }

    var fadeLayer: some View {
        // What scrolls fades out under the pinned rows into a second copy of the backdrop,
        // so nothing shows through their glass and no band marks where they start: under
        // the header and the search field.
        Backdrop()
            .mask(alignment: .topLeading) {
                HStack(alignment: .top, spacing: 0) {
                    if sidebarShown { Color.clear.frame(width: sideWidth + 1) } // the sidebar card clips its own
                    Self.fade(Self.barHeight - 6, 22)
                }
            }
            .allowsHitTesting(false)
    }

    // Drag the sidebar card's edge to resize it.
    var sidebarEdge: some View {
        SidebarResizer(width: $sidebarWidth)
            .padding(.vertical, Self.inset + Self.sidebarRadius)
            .padding(.leading, sideWidth - 4)
    }

    var pinnedRows: some View {
        VStack(spacing: 0) {
            contentHeader
            SearchField(text: $query, focus: $searching)
                .padding(.leading, Self.side)
                .padding(.trailing, trailingSide)
        }
        .padding(.leading, sidebarShown ? sideWidth + 1 : 0)
    }

    // A visible scroll bar narrows the cards; the header and the search field narrow with
    // them, so their ends line up with the cards' (left ones, in Persian).
    var trailingSide: CGFloat { Self.side + max(0, columnWidth - contentWidth) }

    static func fade(_ solid: CGFloat, _ soft: CGFloat) -> some View {
        VStack(spacing: 0) {
            Color.black.frame(height: solid)
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: soft)
        }
    }

    // The top of the sidebar card: the window buttons, the app's name, then new section and
    // more. Its middle is level with the header row beside it.
    var sidebarHeader: some View {
        HStack(spacing: 8) {
            Text("Shortcut Divan")
                .font(.app(15, .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            GlassGroup {
                Button { editing = .section(nil) } label: { GlassIcon(symbol: "plus", size: Self.smallDisc) }
                    .glassDisc()
                    .focusable(false)
                    .help("New Section")
                SwiftUI.Menu {
                    Button("New Section") { editing = .section(nil) }
                    Divider()
                    Button("Import…") { store.importFile() }
                    Button("Export…") { store.exportFile() }
                    Divider()
                    Button("Follow a Shortcuts File…") { store.link() }
                    if store.linkedFile != nil { Button("Stop Following File") { store.unlink() } }
                } label: {
                    GlassIcon(symbol: "ellipsis", size: Self.smallDisc)
                }
                .glassDisc()
                .focusable(false)
                .help("More")
            }
        }
        .padding(.leading, TrafficLights.width - Self.inset)
        .padding(.trailing, Self.listInset)
        // Centered on the window buttons, the same as the header row beside it; the first
        // row below starts level with the search field.
        .frame(height: Self.headerHeight - 2 * Self.inset)
        .padding(.bottom, Self.inset)
        .movesWindow()
    }

    // The content's part of the header row: sidebar toggle, what is shown, and the theme,
    // language and settings buttons. With the sidebar hidden it starts after the window buttons.
    var contentHeader: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.snappy) { sidebarShown.toggle() }
            } label: {
                GlassIcon(symbol: "sidebar.leading", size: Self.disc)
            }
            .glassDisc()
            .focusable(false)
            .help("Toggle Sidebar")
            Spacer(minLength: 8)
            heading
            Spacer(minLength: 8)
            GlassGroup {
                ThemeButton(size: Self.disc)
                LanguageMenu(size: Self.disc)
                SettingsLink { GlassIcon(symbol: "gearshape", size: Self.disc) }
                    .glassDisc()
                    .help("Settings")
            }
            .focusable(false)
        }
        .padding(.leading, sidebarShown ? Self.side : TrafficLights.width)
        .padding(.trailing, trailingSide)
        .frame(height: Self.headerHeight)
        .movesWindow()
    }

    // The title in the middle of the header: the picked section, or all of them.
    @ViewBuilder var heading: some View {
        if let index = store.sections.firstIndex(where: { $0.title == selected }) {
            let section = store.sections[index]
            HStack(spacing: 8) {
                Circle().fill(Color.rosePine(section.accent)).frame(width: 9, height: 9)
                Text(verbatim: section.title).font(.app(15, .semibold)).lineLimit(1)
            }
        } else {
            Text("All Shortcuts").font(.app(15, .semibold)).lineLimit(1)
        }
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
                    .font(.app(15, .bold))
                Text(verbatim: rows.count.formatted())
                    .font(.app(11, .semibold).monospacedDigit())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(accent.opacity(0.15), in: Capsule())
                    .foregroundStyle(accent)
                Spacer(minLength: 0)
                GlassGroup {
                    Button { edit(.row(section: index, row: nil)) } label: { GlassIcon(symbol: "plus", size: 34) }
                        .glassDisc()
                        .focusable(false)
                        .help("Add a shortcut to this section")
                    SwiftUI.Menu { menu() } label: { GlassIcon(symbol: "ellipsis", size: 34) }
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
                .font(.app(11, .semibold))
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
                .font(.app(13.5))
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
            .font(.system(size: 13, weight: .semibold))
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
                        .buttonStyle(KeycapButtonStyle())
                }
            }
            .environment(\.layoutDirection, .leftToRight)
            TextField("Description", text: $row.desc, prompt: Text("split horizontally"))
            Picker("Section", selection: $section) {
                ForEach(Array(sections.enumerated()), id: \.offset) { Text(verbatim: $1).tag($0) }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .safeAreaInset(edge: .bottom) {
            SheetButtons(disabled: row.keys.trimmed.isEmpty || row.desc.trimmed.isEmpty) {
                save(Shortcut(keys: row.keys.trimmed, desc: row.desc.trimmed, only: row.only), section)
            }
        }
        .appLook()
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct SectionEditor: View {
    @State var section: Section
    let save: (Section) -> Void

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
        .scrollDisabled(true)
        .safeAreaInset(edge: .bottom) {
            SheetButtons(disabled: section.title.trimmed.isEmpty) {
                section.title = section.title.trimmed
                save(section)
            }
        }
        .appLook()
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
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

// The sidebar's rows, each a small card: All Shortcuts, then one per section. Drag a section
// to reorder.
struct SidebarList<Menu: View>: View {
    let sections: [Section]
    let total: Int
    @Binding var selected: String?
    @ViewBuilder let menu: (Int) -> Menu
    let move: (_ from: Int, _ to: Int) -> Void
    @State private var dragging: Int?
    @State private var target: Int?

    var body: some View {
        VStack(spacing: 6) {
            SidebarRow(title: "All Shortcuts", symbol: "square.stack", count: total,
                       picked: selected == nil || selected == DivanWindow.all) { selected = DivanWindow.all }
                .padding(.bottom, 6) // a little apart from the sections
            ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                SidebarRow(
                    title: LocalizedStringKey(section.title), verbatim: section.title,
                    accent: section.accent, count: section.rows.filter { $0.only == nil }.count,
                    picked: selected == section.title
                ) { selected = section.title }
                .overlay(alignment: (dragging ?? index) > index ? .top : .bottom) {
                    // Where the dragged section will land: above this row going up, below it going down.
                    if target == index, let dragging, dragging != index {
                        Capsule().fill(Color.accentColor).frame(height: 2).offset(y: dragging > index ? -1 : 1)
                    }
                }
                .onDrag {
                    dragging = index
                    return NSItemProvider(object: section.title as NSString)
                }
                .onDrop(of: [.text], delegate: SectionDrop(index: index, dragging: $dragging, target: $target, move: move))
                .contextMenu { menu(index) }
            }
        }
    }
}

// Moves the window's close, minimize and zoom buttons down to the middle of the header row,
// as far from the window's side as from its top (as in Telegram), and keeps them there as
// the window resizes. Without a title bar macOS puts them near the top edge, out of line
// with everything else.
struct TrafficLights: NSViewRepresentable {
    let centerY: CGFloat
    // Room the three buttons take from the window's edge, with a gap after them, for what
    // comes next in the header.
    static let width: CGFloat = 92

    func makeNSView(context: Context) -> Placer {
        let view = Placer()
        view.centerY = centerY
        return view
    }

    func updateNSView(_ view: Placer, context: Context) {
        view.centerY = centerY
        view.place()
    }

    final class Placer: NSView {
        var centerY: CGFloat = 28
        private var observers: [NSObjectProtocol] = []
        private var watched: Set<ObjectIdentifier> = []
        private var themeWatch: NSKeyValueObservation?
        private var placing = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            watched = []
            themeWatch = nil
            guard let window else { return }
            let names: [Notification.Name] = [
                NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification,
                NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                NSWindow.didExitFullScreenNotification, NSWindow.didChangeScreenNotification,
            ]
            for name in names {
                observe(name, of: window)
            }
            // Switching light and dark lays the title bar out again, back at its own height.
            themeWatch = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
                DispatchQueue.main.async { self?.place() }
            }
            DispatchQueue.main.async { self.place() }
        }

        private func observe(_ name: Notification.Name, of object: AnyObject) {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                self?.place()
            })
        }

        // AppKit lays the title bar out again on its own (on theme changes, focus, hover over
        // the buttons); any frame change of the bar or a button puts them back.
        private func watch(_ view: NSView) {
            guard watched.insert(ObjectIdentifier(view)).inserted else { return }
            view.postsFrameChangedNotifications = true
            observe(NSView.frameDidChangeNotification, of: view)
        }

        override func layout() {
            super.layout()
            place()
        }

        func place() {
            guard !placing, let window, !window.styleMask.contains(.fullScreen),
                  let close = window.standardWindowButton(.closeButton),
                  let minimize = window.standardWindowButton(.miniaturizeButton),
                  let zoom = window.standardWindowButton(.zoomButton),
                  let bar = close.superview, let container = bar.superview else { return }
            placing = true
            defer { placing = false }
            for view in [container, bar, close, minimize, zoom] { watch(view) }
            // The title bar's container grows to the header's height, so the buttons can sit
            // in its middle; it is transparent, and clicks beside the buttons still reach
            // the header below it.
            let height = centerY * 2
            let frame = NSRect(x: container.frame.minX, y: window.frame.height - height,
                               width: container.frame.width, height: height)
            if container.frame != frame { container.frame = frame }
            if bar.frame != container.bounds { bar.frame = container.bounds }
            let size = close.frame.size
            let step = size.width + 6 // the system's spacing between the three
            let rightToLeft = window.windowTitlebarLayoutDirection == .rightToLeft
            let first = centerY - size.width / 2 // same distance from the side as from the top
            for (index, button) in [close, minimize, zoom].enumerated() {
                let offset = first + CGFloat(index) * step
                let x = rightToLeft ? bar.bounds.width - offset - size.width : offset
                let origin = NSPoint(x: x, y: (height - size.height) / 2)
                if button.frame.origin != origin { button.setFrameOrigin(origin) }
            }
        }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}

// A section dropped on another row takes that row's place.
struct SectionDrop: DropDelegate {
    let index: Int
    @Binding var dragging: Int?
    @Binding var target: Int?
    let move: (Int, Int) -> Void

    func validateDrop(info: DropInfo) -> Bool { dragging != nil }
    func dropEntered(info: DropInfo) { target = index }
    func dropExited(info: DropInfo) { if target == index { target = nil } }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        defer { dragging = nil; target = nil }
        guard let from = dragging, from != index else { return false }
        move(from, index)
        return true
    }
}

// A thin handle over the sidebar's edge: drag to resize the sidebar, kept between a width that
// still fits the header buttons and one that leaves the cards room.
struct SidebarResizer: View {
    @Binding var width: Double
    @State private var start: Double?

    static let range = 300.0...440.0

    var body: some View {
        Color.clear
            .frame(width: 9)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                // Screen coordinates, so the direction is the same in both layouts; in Persian
                // the sidebar is on the right and grows to the left.
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        let from = start ?? min(max(width, Self.range.lowerBound), Self.range.upperBound)
                        start = from
                        let delta = LayoutDirection.app == .rightToLeft ? -drag.translation.width : drag.translation.width
                        width = min(max(from + delta, Self.range.lowerBound), Self.range.upperBound)
                    }
                    .onEnded { _ in start = nil }
            )
    }
}

// A sidebar row as a small card: a section's color dot (or a symbol), the name, and a count.
// The picked one is tinted and outlined in its color.
struct SidebarRow: View {
    var title: LocalizedStringKey
    var verbatim: String?
    var symbol: String?
    var accent = "iris"
    let count: Int
    let picked: Bool
    let pick: () -> Void
    @State private var hovering = false

    var body: some View {
        let color = Color.rosePine(accent)
        HStack(spacing: 10) {
            Group {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(.secondary)
                } else {
                    Circle().fill(color).frame(width: 9, height: 9)
                }
            }
            .frame(width: 16)
            Group {
                if let verbatim { Text(verbatim: verbatim) } else { Text(title) }
            }
            .font(.app(13.5, picked ? .semibold : .regular))
            .lineLimit(1)
            Spacer(minLength: 4)
            Text(verbatim: count.formatted())
                .font(.app(11, .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
            shape.fill(picked ? color.opacity(0.20) : Color.primary.opacity(hovering ? 0.08 : 0.045))
                .overlay(shape.strokeBorder(picked ? color.opacity(0.45) : Color.primary.opacity(0.08), lineWidth: 0.75))
        }
        .contentShape(Rectangle())
        // A tap rather than a button, so a row can also be dragged.
        .onTapGesture(perform: pick)
        .accessibilityAddTraits(.isButton)
        .onHover { hovering = $0 }
    }
}

// A wide search field at the top of the list, as in launcher apps. ⌘F focuses it, ⎋ clears it.
struct SearchField: View {
    static let height: CGFloat = 38

    @Binding var text: String
    var focus: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search shortcuts", text: $text)
                .textFieldStyle(.plain)
                .font(.app(15))
                .focused(focus)
            if text.isEmpty {
                Text(verbatim: "⌘F")
                    .font(.app(11, .medium))
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
                HStack(spacing: 8) {
                    Button("Follow a Shortcuts File…", systemImage: "link") { store.link() }
                        .buttonStyle(TintButtonStyle(accent: "iris"))
                    if store.linkedFile != nil {
                        Button("Stop Following File", systemImage: "xmark") { store.unlink() }
                            .buttonStyle(TintButtonStyle(accent: "gold"))
                    }
                }
            } footer: {
                Text("A followed file is read, watched for changes, and saved back to when you edit here.")
                    .foregroundStyle(.secondary)
            }
            SwiftUI.Section {
                HStack(spacing: 8) {
                    Button("Import…", systemImage: "square.and.arrow.down") { store.importFile() }
                        .buttonStyle(TintButtonStyle(accent: "foam"))
                    Button("Export…", systemImage: "square.and.arrow.up") { store.exportFile() }
                        .buttonStyle(TintButtonStyle(accent: "pine"))
                    Spacer()
                    Button("Restore Default Shortcuts…", systemImage: "arrow.counterclockwise", role: .destructive) {
                        store.restoreDefaults()
                    }
                    .buttonStyle(TintButtonStyle(accent: "love"))
                }
            }
        }
        .formStyle(.grouped)
        .appLook()
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

// The window's backdrop runs up under the title bar in one piece: no toolbar band
// (macOS 15) and no blurred strip where content scrolls under it (macOS 26).
extension View {
    @ViewBuilder func clearToolbar() -> some View {
        if #available(macOS 15, *) { toolbarBackgroundVisibility(.hidden, for: .windowToolbar) } else { self }
    }

    @ViewBuilder func noTopEdgeEffect() -> some View {
        if #available(macOS 26, *) { scrollEdgeEffectHidden(true, for: .top) } else { self }
    }
}

extension View {
    // Without a title bar, the window moves by dragging an empty spot of the top bar (macOS 15).
    @ViewBuilder func movesWindow() -> some View {
        if #available(macOS 15, *) { contentShape(Rectangle()).gesture(WindowDragGesture()) } else { self }
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

// Text buttons tinted with a Rosé Pine color, in the keycaps' and row tiles' style: a soft
// fill, a thin border in the same color, a stronger fill on hover and press. `prominent`
// fills it for the main action of a sheet.
struct TintButtonStyle: ButtonStyle {
    var accent = "iris"
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        Tinted(configuration: configuration, color: Color.rosePine(accent), prominent: prominent)
    }

    struct Tinted: View {
        let configuration: Configuration
        let color: Color
        let prominent: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false

        var body: some View {
            let fill = prominent ? 0.85 : configuration.isPressed ? 0.32 : hovering ? 0.22 : 0.14
            configuration.label
                .font(.app(13, .medium))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(prominent ? Color.white : color)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(color.opacity(configuration.isPressed && prominent ? 0.7 : fill),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(color.opacity(prominent ? 0 : 0.35), lineWidth: 0.5))
                .opacity(enabled ? 1 : 0.45)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

// A key symbol to add in the shortcut editor, drawn as a keycap.
struct KeycapButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.app(13, .semibold))
            .frame(minWidth: 26, minHeight: 24)
            .background(Color.primary.opacity(configuration.isPressed ? 0.22 : 0.10),
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5))
            .contentShape(Rectangle())
    }
}

extension View {
    // Settings and the edit sheets in the main window's look: its colored backdrop behind
    // the form's groups.
    func appLook() -> some View {
        scrollContentBackground(.hidden).background(Backdrop()).font(.app(13))
    }
}

// Cancel and the main action at the bottom of an edit sheet, in the app's button style.
struct SheetButtons: View {
    let disabled: Bool
    let save: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 8) {
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(TintButtonStyle(accent: "text"))
                .keyboardShortcut(.cancelAction)
            Button("Save") {
                save()
                dismiss()
            }
            .buttonStyle(TintButtonStyle(accent: "iris", prominent: true))
            .keyboardShortcut(.defaultAction)
            .disabled(disabled)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
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
            .font(.system(size: (size * 0.47).rounded(), weight: .medium))
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
