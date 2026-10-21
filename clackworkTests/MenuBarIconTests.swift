import AppKit
import Testing
@testable import clackwork

/// Menu bar icon states (FR-14).
@MainActor
struct MenuBarIconTests {
    @Test func stateFollowsEnabledAndMuted() {
        #expect(MenuBarIcon.State(isEnabled: true, isMuted: false) == .on)
        #expect(MenuBarIcon.State(isEnabled: true, isMuted: true) == .muted)
        #expect(MenuBarIcon.State(isEnabled: false, isMuted: false) == .off)
        // Turning sound off while muted shows off, not muted.
        #expect(MenuBarIcon.State(isEnabled: false, isMuted: true) == .off)
    }

    @Test func everyStateIsATemplateImageWithItsOwnDescription() {
        let states: [MenuBarIcon.State] = [.on, .muted, .paused, .off]
        let images = states.map(MenuBarIcon.image(for:))
        #expect(images.allSatisfy { $0.isTemplate && $0.size == NSSize(width: 18, height: 18) })
        #expect(Set(images.compactMap(\.accessibilityDescription)).count == states.count)
    }
}
