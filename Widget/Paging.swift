// Buttons on the widget: page through a long section, or step to the next section.
// Widgets can't scroll, so the position is kept here and the widget is redrawn.
import AppIntents
import Foundation

struct Position: Codable {
    var shift = 0 // sections moved past the configured one
    var page = 0
}

// One position per widget configuration (the picked sections), in the extension's defaults.
enum Positions {
    static func get(_ key: String) -> Position {
        guard let data = UserDefaults.standard.data(forKey: "position." + key),
              let position = try? JSONDecoder().decode(Position.self, from: data) else { return Position() }
        return position
    }

    static func update(_ key: String, _ change: (inout Position) -> Void) {
        var position = get(key)
        change(&position)
        UserDefaults.standard.set(try? JSONEncoder().encode(position), forKey: "position." + key)
    }

    // To another section, on its first page.
    static func step(_ key: String, by delta: Int) {
        update(key) {
            $0.shift += delta
            $0.page = 0
        }
    }
}

struct TurnPage: AppIntent {
    static let title: LocalizedStringResource = "Turn Page"
    static let isDiscoverable = false

    @Parameter(title: "Widget") var key: String
    @Parameter(title: "By") var delta: Int

    init() {}
    init(key: String, delta: Int) {
        self.key = key
        self.delta = delta
    }

    // The view wraps the page number around the section's page count.
    func perform() async throws -> some IntentResult {
        Positions.update(key) { $0.page += delta }
        return .result()
    }
}

struct NextSection: AppIntent {
    static let title: LocalizedStringResource = "Next Section"
    static let isDiscoverable = false

    @Parameter(title: "Widget") var key: String

    init() {}
    init(key: String) { self.key = key }

    func perform() async throws -> some IntentResult {
        Positions.step(key, by: 1)
        return .result()
    }
}

struct PreviousSection: AppIntent {
    static let title: LocalizedStringResource = "Previous Section"
    static let isDiscoverable = false

    @Parameter(title: "Widget") var key: String

    init() {}
    init(key: String) { self.key = key }

    func perform() async throws -> some IntentResult {
        Positions.step(key, by: -1)
        return .result()
    }
}
