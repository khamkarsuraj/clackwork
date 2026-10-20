import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import clackwork

/// Global shortcuts table: defaults, reassignment and persistence.
@MainActor
struct ShortcutStoreTests {
    private let suiteName = "clackworkTests.shortcuts.\(UUID().uuidString)"
    private var defaults: UserDefaults { UserDefaults(suiteName: suiteName)! }

    @Test func startsWithTheDefaults() {
        let store = ShortcutStore(defaults: defaults)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        for action in ShortcutAction.allCases {
            #expect(store.combo(for: action) == action.defaultCombo)
        }
    }

    @Test func defaultsAllHaveModifiersAndAreDistinct() {
        let combos = ShortcutAction.allCases.map(\.defaultCombo)
        #expect(Set(combos).count == combos.count)
        #expect(combos.allSatisfy { $0.hasModifier })
    }

    @Test func takingAnotherActionsComboUnassignsIt() {
        let store = ShortcutStore(defaults: defaults)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let muteCombo = ShortcutAction.toggleMute.defaultCombo
        store.set(muteCombo, for: .toggleSound)
        #expect(store.combo(for: .toggleSound) == muteCombo)
        #expect(store.combo(for: .toggleMute) == nil)
    }

    @Test func changesSurviveAReload() {
        let combo = KeyCombo(keyCode: UInt16(kVK_ANSI_J), modifiers: [.command, .shift])
        do {
            let store = ShortcutStore(defaults: defaults)
            store.set(combo, for: .volumeUp)
        }
        let reloaded = ShortcutStore(defaults: defaults)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        #expect(reloaded.combo(for: .volumeUp) == combo)
        #expect(reloaded.combo(for: .volumeDown) == ShortcutAction.volumeDown.defaultCombo)
    }

    @Test func restoreDefaultsUndoesChanges() {
        let store = ShortcutStore(defaults: defaults)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        store.set(ShortcutAction.toggleMute.defaultCombo, for: .toggleSound)
        store.restoreDefaults()
        for action in ShortcutAction.allCases {
            #expect(store.combo(for: action) == action.defaultCombo)
        }
    }

    // MARK: Changed defaults reach users who never customized that action

    /// The actions with an entry in the stored JSON.
    private var storedActions: Set<String> {
        guard let data = defaults.data(forKey: "shortcuts"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return Set(json.keys)
    }

    @Test func storesOnlyWhatDiffersFromTheDefaults() {
        let store = ShortcutStore(defaults: defaults)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        #expect(storedActions.isEmpty)
        store.set(KeyCombo(keyCode: UInt16(kVK_ANSI_J), modifiers: [.command, .shift]), for: .volumeUp)
        #expect(storedActions == ["volumeUp"])

        // Taking mute's combo stores both: the new combo and mute's "unassigned".
        store.set(ShortcutAction.toggleMute.defaultCombo, for: .nextKeyboard)
        #expect(storedActions == ["volumeUp", "nextKeyboard", "toggleMute"])

        store.restoreDefaults()
        #expect(storedActions.isEmpty)
    }

    private let oldSoundCombo = KeyCombo(keyCode: UInt16(kVK_ANSI_K), modifiers: [.control, .option])

    @Test func aStoredRetiredDefaultReadsAsTheCurrentDefaultWhileMigrating() {
        // ⌃⌥K was the sound on/off default; a stored copy of it was the default at the time, not a choice.
        let resolved = ShortcutStore.resolve(stored: [.toggleSound: oldSoundCombo], migratingRetiredDefaults: true)
        #expect(resolved[.toggleSound] == ShortcutAction.toggleSound.defaultCombo)
        #expect(ShortcutAction.toggleSound.defaultCombo.display == "⌃ ⌥ O")
    }

    @Test func aRetiredDefaultRecordedOnPurposeIsKept() {
        let resolved = ShortcutStore.resolve(stored: [.toggleSound: oldSoundCombo], migratingRetiredDefaults: false)
        #expect(resolved[.toggleSound] == oldSoundCombo)
    }

    @Test func aRetiredDefaultStaysWhenTheNewDefaultIsTaken() {
        let resolved = ShortcutStore.resolve(stored: [
            .toggleSound: oldSoundCombo,
            .volumeUp: ShortcutAction.toggleSound.defaultCombo,
        ], migratingRetiredDefaults: true)
        #expect(resolved[.toggleSound] == oldSoundCombo, "no two actions may share a combo")
        #expect(resolved[.volumeUp] == ShortcutAction.toggleSound.defaultCombo)
    }

    @Test func aMissingEntryTakesTheDefaultUnlessAnotherActionHasIt() {
        let resolved = ShortcutStore.resolve(stored: [.toggleMute: ShortcutAction.volumeUp.defaultCombo],
                                             migratingRetiredDefaults: false)
        #expect(resolved[.toggleMute] == ShortcutAction.volumeUp.defaultCombo)
        #expect(resolved[.volumeUp] == .some(nil), "left unassigned rather than shared")
    }

    @Test func unassignedStaysUnassignedAcrossReloads() {
        let resolved = ShortcutStore.resolve(stored: [.toggleMute: nil], migratingRetiredDefaults: false)
        #expect(resolved[.toggleMute] == .some(nil))
    }

    @Test func migrationFromTheOldFormatRunsOnceAndSticks() throws {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        // Version 1 stored every combo, with no version key. Sound on/off was ⌃⌥K.
        let old: [String: Any] = [
            "toggleSound": ["combo": ["keyCode": Int(oldSoundCombo.keyCode), "modifiers": Int(oldSoundCombo.modifiers)]],
            "toggleMute": ["combo": ["keyCode": Int(kVK_ANSI_M), "modifiers": Int(oldSoundCombo.modifiers)]],
        ]
        defaults.set(try JSONSerialization.data(withJSONObject: old), forKey: "shortcuts")

        let migrated = ShortcutStore(defaults: defaults)
        #expect(migrated.combo(for: .toggleSound) == ShortcutAction.toggleSound.defaultCombo)
        #expect(migrated.combo(for: .toggleMute) == ShortcutAction.toggleMute.defaultCombo)
        #expect(storedActions.isEmpty, "defaults are no longer written out")
        #expect(defaults.integer(forKey: "shortcutsVersion") == ShortcutStore.currentVersion)

        // From now on ⌃⌥K is a choice like any other.
        migrated.set(oldSoundCombo, for: .toggleSound)
        #expect(ShortcutStore(defaults: defaults).combo(for: .toggleSound) == oldSoundCombo)
    }
}
