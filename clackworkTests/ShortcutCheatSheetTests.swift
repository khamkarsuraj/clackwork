import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import clackwork

/// Shortcut cheat sheet (issue #31), opened by the "Show keyboard shortcuts" global shortcut.
@MainActor
struct ShortcutCheatSheetTests {
    private let suiteName = "clackworkTests.cheatsheet.\(UUID().uuidString)"
    private var defaults: UserDefaults { UserDefaults(suiteName: suiteName)! }

    @Test func hasItsOwnGlobalShortcut() {
        #expect(ShortcutAction.showShortcuts.defaultCombo.display == "⌃ ⌥ S")
        #expect(ShortcutAction.showShortcuts.label == "Show keyboard shortcuts")
    }

    @Test func listsEveryShortcutWithItsDefaultCombo() {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let rows = ShortcutCheatSheet.rows(from: ShortcutStore(defaults: defaults))
        #expect(rows.map(\.id) == ShortcutAction.allCases.map(\.id))
        #expect(rows.map(\.label) == ShortcutAction.allCases.map(\.label))
        #expect(rows.map(\.keys) == ShortcutAction.allCases.map { $0.defaultCombo.display })
        #expect(rows.contains { $0.label == "Show keyboard shortcuts" && $0.keys == "⌃ ⌥ S" })
    }

    @Test func reflectsCustomizedAndUnassignedShortcuts() {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ShortcutStore(defaults: defaults)
        // Taking mute's combo for "next keyboard" leaves mute unassigned.
        store.set(ShortcutAction.toggleMute.defaultCombo, for: .nextKeyboard)
        store.set(KeyCombo(keyCode: UInt16(kVK_ANSI_J), modifiers: [.command, .shift]), for: .showShortcuts)

        let rows = Dictionary(uniqueKeysWithValues: ShortcutCheatSheet.rows(from: store).map { ($0.id, $0.keys) })
        #expect(rows[ShortcutAction.nextKeyboard.id] == "⌃ ⌥ M")
        #expect(rows[ShortcutAction.toggleMute.id] == .some(nil))
        #expect(rows[ShortcutAction.showShortcuts.id] == "⇧ ⌘ J")
    }

    @Test func shortcutTogglesTheSheetAndBringsTheWindowUp() {
        let router = WindowRouter()
        router.isAppActive = { true }
        var windowOpened = 0
        router.openMainWindow = { windowOpened += 1 }
        #expect(!router.isShowingShortcutSheet)

        router.toggleShortcutSheet()
        #expect(router.isShowingShortcutSheet)
        #expect(windowOpened == 1, "with the window closed, the shortcut opens it")

        router.toggleShortcutSheet()
        #expect(!router.isShowingShortcutSheet, "pressed again in front, it closes the sheet")
        #expect(windowOpened == 1)
    }

    @Test func fromAnotherAppTheShortcutAlwaysEndsWithTheSheetVisible() {
        let router = WindowRouter()
        router.isAppActive = { false }
        var windowOpened = 0
        router.openMainWindow = { windowOpened += 1 }

        router.toggleShortcutSheet()
        router.toggleShortcutSheet()
        #expect(router.isShowingShortcutSheet, "the sheet was left up behind another app; bring it back, don't hide it")
        #expect(windowOpened == 2)
    }

    @Test func hotKeyRoutesToTheSheetWithoutAHUD() {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = AppState(defaults: defaults, engine: nil)
        let store = ShortcutStore(defaults: defaults)
        // While a shortcut is being recorded nothing is registered system-wide, which keeps
        // this test from taking the real hot keys away from a running Clackwork.
        store.recording = .toggleMute
        let hud = HUDController(reduceMotion: { true })
        let router = WindowRouter()
        router.isAppActive = { true }
        let center = HotKeyCenter(appState: state, shortcuts: store, hud: hud, router: router)
        let wasEnabled = state.isEnabled

        center.perform(.showShortcuts)
        #expect(router.isShowingShortcutSheet)
        #expect(!hud.isVisible, "the sheet is its own feedback")
        #expect(state.isEnabled == wasEnabled, "showing the sheet changes no sound state")

        center.perform(.showShortcuts)
        #expect(!router.isShowingShortcutSheet)
    }
}
