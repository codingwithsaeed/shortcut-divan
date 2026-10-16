// The app's copy of the shortcuts: loads and saves the data file the widget reads, and can
// follow a shortcuts file elsewhere (a dotfiles repo, a synced folder) instead.
import AppKit
import Observation
import UniformTypeIdentifiers
import WidgetKit

@Observable
final class Store {
    static let shared = Store()

    var sections: [Section] = []
    var error: String?
    // A shortcuts file the user picked: read from it, saved back to it, watched for changes.
    private(set) var linkedFile: URL? {
        didSet { UserDefaults.standard.set(linkedFile?.path, forKey: "linkedFile") }
    }

    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?

    private init() {
        linkedFile = UserDefaults.standard.string(forKey: "linkedFile").map { URL(fileURLWithPath: $0) }
        reload()
    }

    // Read the linked file (copying it for the widget) or the data file.
    func reload() {
        if let linkedFile {
            do {
                sections = try Shortcuts.decode(Data(contentsOf: linkedFile))
                try writeDataFile()
                watch(linkedFile)
            } catch {
                self.error = String(localized: "Couldn't read \(linkedFile.path): \(error.localizedDescription)")
                sections = Shortcuts.loadAll()
            }
        } else {
            sections = Shortcuts.loadAll()
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    // Save every change: to the linked file if there is one, and for the widget.
    func commit() {
        do {
            if let linkedFile {
                try Data(Shortcuts.format(sections).utf8).write(to: linkedFile)
            }
            try writeDataFile()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            self.error = String(localized: "Couldn't save: \(error.localizedDescription)")
        }
    }

    private func writeDataFile() throws {
        let file = Shortcuts.dataFile
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(Shortcuts.format(sections).utf8).write(to: file, options: .atomic)
    }

    // MARK: menu commands

    func importFile() {
        guard let url = openPanel(title: String(localized: "Import Shortcuts")),
              let imported = read(url),
              confirm(String(localized: "Replace your shortcuts with the \(imported.count) sections in “\(url.lastPathComponent)”?"),
                      button: String(localized: "Replace"))
        else { return }
        sections = imported
        commit()
    }

    func exportFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "shortcuts.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(Shortcuts.format(sections).utf8).write(to: url, options: .atomic)
        } catch {
            self.error = String(localized: "Couldn't save: \(error.localizedDescription)")
        }
    }

    // Follow a file: its shortcuts replace the current ones, and edits here go back to it.
    func link() {
        guard let url = openPanel(title: String(localized: "Follow a Shortcuts File")), read(url) != nil else { return }
        linkedFile = url
        reload()
    }

    func unlink() {
        watcher?.cancel()
        watcher = nil
        linkedFile = nil
    }

    func restoreDefaults() {
        guard confirm(String(localized: "Replace all your shortcuts with the defaults?"), button: String(localized: "Replace")),
              let url = Shortcuts.defaultsFile, let defaults = read(url)
        else { return }
        sections = defaults
        commit()
    }

    // MARK: helpers

    private func read(_ url: URL) -> [Section]? {
        do {
            return try Shortcuts.decode(Data(contentsOf: url))
        } catch {
            self.error = String(localized: "“\(url.lastPathComponent)” isn't a shortcuts file: \(error.localizedDescription)")
            return nil
        }
    }

    private func openPanel(title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func confirm(_ message: String, button: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: String(localized: "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    // Editors often save by replacing the file, so watch again after every event.
    private func watch(_ url: URL) {
        watcher?.cancel()
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.reload() }
            source.cancel()
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }
}
