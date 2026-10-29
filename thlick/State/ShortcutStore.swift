import Combine
import Foundation

/// The user's shortcut assignments, persisted as JSON in UserDefaults.
///
/// Only what differs from the defaults is stored: a customized combo, or nil for an action
/// the user left unassigned after its combo was taken by another action. Anything missing
/// means "use the default", so a changed default reaches everyone who never customized
/// that action.
///
/// Earlier versions stored every combo, so a user from then has the old default on disk as
/// if chosen. Bumping `currentVersion` when a default is retired migrates such a copy once
/// (see `ShortcutAction.retiredDefaults`); after that, recording the old combo on purpose
/// is a choice and is kept.
final class ShortcutStore: ObservableObject {
    private static let key = "shortcuts"
    private static let versionKey = "shortcutsVersion"
    /// 1: every combo stored. 2: only differences stored; ⌃⌥K retired for sound on/off.
    static let currentVersion = 2

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
        let migrating = defaults.integer(forKey: Self.versionKey) < Self.currentVersion
        combos = Self.resolve(stored: Self.load(from: defaults), migratingRetiredDefaults: migrating)
        if migrating {
            // Written back once, so the outcome never changes on a later launch.
            save()
            defaults.set(Self.currentVersion, forKey: Self.versionKey)
        }
    }

    /// Fills in defaults for actions that have no stored entry. While migrating, a stored
    /// combo that is a retired default counts as "no entry" too. The current default is
    /// skipped if another action already uses it, so two actions never end up sharing a
    /// shortcut; a retired combo stays in that case, and a missing one is left unassigned.
    static func resolve(stored: [ShortcutAction: KeyCombo?],
                        migratingRetiredDefaults: Bool) -> [ShortcutAction: KeyCombo?] {
        var result: [ShortcutAction: KeyCombo?] = [:]
        var wantsDefault: [ShortcutAction] = []
        for action in ShortcutAction.allCases {
            switch stored[action] {
            case .none:
                wantsDefault.append(action)
            case .some(.some(let combo)) where migratingRetiredDefaults && action.retiredDefaults.contains(combo):
                wantsDefault.append(action)
                result[action] = combo
            case .some(let combo):
                result[action] = combo
            }
        }
        for action in wantsDefault {
            let taken = result.contains { $0.key != action && $0.value == action.defaultCombo }
            if !taken {
                result[action] = action.defaultCombo
            } else if result[action] == nil {
                result[action] = .some(nil)
            }
        }
        return result
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

    private static func load(from defaults: UserDefaults) -> [ShortcutAction: KeyCombo?] {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode([String: Stored].self, from: data) else { return [:] }
        return ShortcutAction.allCases.reduce(into: [:]) { result, action in
            if let entry = stored[action.rawValue] { result[action] = entry.combo }
        }
    }

    private func save() {
        let stored = combos
            .filter { $0.value != $0.key.defaultCombo }
            .map { ($0.key.rawValue, Stored(combo: $0.value)) }
        if let data = try? JSONEncoder().encode(Dictionary(uniqueKeysWithValues: stored)) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
