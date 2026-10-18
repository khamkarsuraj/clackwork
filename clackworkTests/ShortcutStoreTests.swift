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
}
