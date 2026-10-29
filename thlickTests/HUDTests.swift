import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import thlick

/// Shortcut HUD (issue #50): what each shortcut shows.
struct HUDContentTests {
    private let brown = KeyboardProfile.defaultProfile

    private func content(_ action: ShortcutAction, isEnabled: Bool = true, isMuted: Bool = false,
                         volume: Double = 0.6, combo: KeyCombo? = nil) -> HUDContent {
        HUDContent(after: action, isEnabled: isEnabled, isMuted: isMuted,
                   profile: brown, volume: volume, combo: combo ?? action.defaultCombo)
    }

    @Test func muteShowsTheStateAndHowToUndoIt() {
        let muted = content(.toggleMute, isMuted: true)
        #expect(muted.title == "Muted")
        #expect(muted.detail == "⌃⌥M to unmute")
        #expect(muted.icon == .symbol("speaker.slash.fill"))

        let unmuted = content(.toggleMute, isMuted: false)
        #expect(unmuted.title == "Unmuted")
        #expect(unmuted.detail == "⌃⌥M to mute")
    }

    @Test func soundToggleShowsTheStateAndHowToUndoIt() {
        #expect(content(.toggleSound, isEnabled: false).title == "Sound off")
        #expect(content(.toggleSound, isEnabled: false).detail == "⌃⌥O to turn on")
        #expect(content(.toggleSound, isEnabled: true).title == "Sound on")
        #expect(content(.toggleSound, isEnabled: true).detail == "⌃⌥O to turn off")
    }

    @Test func hintUsesTheCustomizedShortcut() {
        let custom = KeyCombo(keyCode: UInt16(kVK_ANSI_J), modifiers: [.command, .shift])
        #expect(content(.toggleMute, isMuted: true, combo: custom).detail == "⇧⌘J to unmute")
    }

    @Test func unassignedShortcutShowsNoHint() {
        let noCombo = HUDContent(after: .toggleMute, isEnabled: true, isMuted: true,
                                 profile: brown, volume: 0.6, combo: nil)
        #expect(noCombo.detail == nil)
        #expect(noCombo.accessibilityLabel == "Muted")
    }

    @Test func keyboardChangeShowsTheProfileAndItsPosition() {
        let next = content(.nextKeyboard)
        #expect(next.title == "Walnut Bump")
        #expect(next.detail == "Keyboard 2 of \(KeyboardProfile.all.count)")
        #expect(next.icon == .profile(brown))
        #expect(content(.previousKeyboard) == next)
    }

    @Test func volumeShowsAPercentageAndABar() {
        let up = content(.volumeUp, volume: 0.6)
        #expect(up.title == "Volume")
        #expect(up.value == "60%")
        #expect(up.progress == 0.6)
        #expect(up.detail == nil)
        #expect(up.accessibilityLabel == "Volume, 60%")
        #expect(content(.volumeDown, volume: 0).icon == .symbol("speaker.slash.fill"))
        #expect(content(.volumeDown, volume: 0).value == "0%")
    }

    @Test func compactComboHasNoSpaces() {
        #expect(ShortcutAction.nextKeyboard.defaultCombo.compactDisplay == "⌃⌥→")
        #expect(ShortcutAction.nextKeyboard.defaultCombo.display == "⌃ ⌥ →")
    }
}

/// Shortcut HUD (issue #50): showing, updating and hiding the panel.
@MainActor
struct HUDControllerTests {
    private let muted = HUDContent(after: .toggleMute, isEnabled: true, isMuted: true,
                                   profile: .defaultProfile, volume: 0.6, combo: ShortcutAction.toggleMute.defaultCombo)
    private let volume = HUDContent(volume: 0.5)

    @Test func staysUpForOnePointTwoSeconds() {
        #expect(HUDController.displayDuration == 1.2)
    }

    // These suspend with `await` rather than spinning the main run loop: a nested
    // RunLoop.run services timers but blocks every other main-actor task, including the
    // scheduled work of whichever test is suspended at the time (see TestSupport).

    @Test func showsThenHidesByItself() async throws {
        let hud = HUDController(reduceMotion: { true })
        #expect(!hud.isVisible)
        hud.show(muted)
        #expect(hud.isVisible)
        #expect(hud.content == muted)

        try await waitUntil { !hud.isVisible }
        #expect(!hud.isVisible)
        #expect(hud.content == nil)
    }

    @Test func anotherShortcutUpdatesItInPlaceAndRestartsTheTimer() async throws {
        let hud = HUDController(reduceMotion: { true })
        hud.show(muted)
        try await Task.sleep(for: .seconds(0.8))
        hud.show(volume)
        #expect(hud.content == volume)
        // 0.8 + 0.6 is past the first timer; the second keeps it up.
        try await Task.sleep(for: .seconds(0.6))
        #expect(hud.isVisible)
        try await waitUntil { !hud.isVisible }
        #expect(!hud.isVisible)
        hud.hide()
    }

    @Test func hidingWithoutReduceMotionFadesOutThenHides() async throws {
        let hud = HUDController(reduceMotion: { false })
        hud.show(muted)
        hud.hide()
        #expect(hud.isVisible) // still fading
        try await waitUntil { !hud.isVisible }
        #expect(!hud.isVisible)
    }

    @Test func panelNeverTakesFocusOrClicks() {
        let hud = HUDController(reduceMotion: { true })
        hud.show(muted)
        defer { hud.hide() }
        let panel = try! #require(hud.panel)
        #expect(panel.ignoresMouseEvents)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(!panel.canBecomeKey)
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(panel.frame.size == HUDView.size)
    }

    @Test func sitsAtTheBottomCenterOfAScreen() {
        let origin = HUDController.origin(for: HUDView.size)
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let frame = CGRect(origin: origin, size: HUDView.size)
        #expect(screens.contains { $0.visibleFrame.contains(frame) })
    }
}

/// "Show HUD for shortcuts" setting.
@MainActor
struct HUDSettingTests {
    private let suiteName = "thlickTests.hud.\(UUID().uuidString)"

    @Test func isOnByDefaultAndRemembered() {
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let defaults = UserDefaults(suiteName: suiteName)!
        let state = AppState(defaults: defaults, engine: nil)
        #expect(state.showHUD)
        state.showHUD = false
        #expect(!AppState(defaults: defaults, engine: nil).showHUD)
    }
}
