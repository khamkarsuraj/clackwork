import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import thlick

/// VoiceOver reads key combinations by name, not by symbol (PRD NFR Accessibility, issue #40).
@MainActor
struct AccessibilityTests {
    private let suiteName = "thlickTests.accessibility.\(UUID().uuidString)"

    @Test func combosAreSpokenByName() {
        #expect(ShortcutAction.toggleSound.defaultCombo.spokenDescription == "Control-Option-O")
        #expect(ShortcutAction.nextKeyboard.defaultCombo.spokenDescription == "Control-Option-Right Arrow")
        #expect(ShortcutAction.volumeDown.defaultCombo.spokenDescription == "Control-Option-Down Arrow")
        let combo = KeyCombo(keyCode: UInt16(kVK_Space), modifiers: [.command, .shift])
        #expect(combo.spokenDescription == "Shift-Command-Space", "Apple's modifier order, like the symbols")
    }

    @Test func everyDefaultComboHasAName() {
        for action in ShortcutAction.allCases {
            #expect(!action.defaultCombo.spokenDescription.contains("Key "), "\(action) needs a spoken key name")
        }
    }

    @Test func cheatSheetRowsCarryTheSpokenCombo() {
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let store = ShortcutStore(defaults: UserDefaults(suiteName: suiteName)!)
        let rows = ShortcutCheatSheet.rows(from: store)
        #expect(rows.map(\.spokenKeys) == ShortcutAction.allCases.map { $0.defaultCombo.spokenDescription })
    }
}
