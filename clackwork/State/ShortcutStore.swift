import Combine
import Foundation

/// The user's shortcut assignments, persisted as JSON in UserDefaults.
///
/// An action can be unassigned (nil) when its combo was taken by another action.
/// Unassigned actions are stored explicitly so they stay unassigned across launches.
final class ShortcutStore: ObservableObject {
    private static let key = "shortcuts"

    /// Stored form: a missing entry means "use the default", a nil combo means "unassigned".
    private struct Stored: Codable {
        var combo: KeyCombo?
    }

    @Published private(set) var combos: [ShortcutAction: KeyCombo?] {
        didSet { save() }
    }

    /// The action currently being recorded in Settings; hot keys pause while this is set.
    @Published var recording: ShortcutAction?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var stored: [String: Stored] = [:]
        if let data = defaults.data(forKey: Self.key) {
            stored = (try? JSONDecoder().decode([String: Stored].self, from: data)) ?? [:]
        }
        combos = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { action in
            (action, stored[action.rawValue].map(\.combo) ?? action.defaultCombo)
        })
    }

    func combo(for action: ShortcutAction) -> KeyCombo? {
        combos[action] ?? nil
    }

    /// Assigns a combo. Any other action using the same combo becomes unassigned,
    /// so two actions never share one shortcut.
    func set(_ combo: KeyCombo, for action: ShortcutAction) {
        var next = combos
        for (other, existing) in next where other != action && existing == combo {
            next[other] = .some(nil)
        }
        next[action] = combo
        combos = next
    }

    func restoreDefaults() {
        combos = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaultCombo) })
    }

    private func save() {
        let stored = Dictionary(uniqueKeysWithValues: combos.map { ($0.key.rawValue, Stored(combo: $0.value)) })
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
