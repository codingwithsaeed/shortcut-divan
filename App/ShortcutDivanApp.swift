// Shortcut Divan: your keyboard shortcuts in a desktop widget, and this window to browse,
// search and edit them. A click on the widget opens the window on that widget's section.
// `open -g -a "Shortcut Divan" --args --reload` only refreshes the widgets and quits.
import SwiftUI
import WidgetKit

@main
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
        .defaultSize(width: 780, height: 580)
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
    @State private var selected: String?
    @State private var query = ""
    @State private var editing: Editing?
    @State private var deleting: Editing?

    var body: some View {
        NavigationSplitView {
            List(Array(store.sections.enumerated()), id: \.offset, selection: $selected) { index, section in
                Label {
                    Text(verbatim: section.title)
                } icon: {
                    Circle().fill(Color.rosePine(section.accent)).frame(width: 8, height: 8)
                }
                .tag(section.title)
                .contextMenu { sectionMenu(index) }
            }
            .environment(\.layoutDirection, .app)
            .navigationSplitViewColumnWidth(min: 170, ideal: 200)
            .safeAreaInset(edge: .bottom) { linkedFooter }
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
                .background(Backdrop())
                .onChange(of: selected) { _, title in
                    guard let title else { return }
                    withAnimation { proxy.scrollTo(title, anchor: .top) }
                }
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: Text("Search shortcuts"))
        .toolbar {
            Button("New Section", systemImage: "plus") { editing = .section(nil) }
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
        .onExitCommand { NSApp.keyWindow?.close() }
        .frame(minWidth: 680, minHeight: 480)
    }

    @ViewBuilder var linkedFooter: some View {
        if let file = store.linkedFile {
            HStack(spacing: 6) {
                Image(systemName: "link")
                Text("Following \(file.lastPathComponent)")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(file.path)
                Spacer(minLength: 0)
                Button("Stop", systemImage: "xmark.circle.fill") { store.unlink() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Stop following this file")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(10)
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
            return words.isEmpty || !rows.isEmpty ? (index, rows) : nil
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
                Button("Add Shortcut", systemImage: "plus") { edit(.row(section: index, row: nil)) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .focusable(false)
                    .help("Add a shortcut to this section")
                SwiftUI.Menu { menu() } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
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
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .glassCard(cornerRadius: 16)
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
            Circle().fill(Color.rosePine("iris").opacity(0.22)).frame(width: 520).blur(radius: 120)
                .offset(x: -220, y: -200)
            Circle().fill(Color.rosePine("rose").opacity(0.20)).frame(width: 460).blur(radius: 120)
                .offset(x: 260, y: 60)
            Circle().fill(Color.rosePine("foam").opacity(0.18)).frame(width: 420).blur(radius: 120)
                .offset(x: -60, y: 320)
        }
        .ignoresSafeArea()
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
