import AppKit
import Foundation
import Testing
@testable import clackwork

/// "Show icon in Dock" setting (FR-19).
@MainActor
struct DockIconTests {
    private let suiteName = "clackworkTests.dock.\(UUID().uuidString)"

    @Test func defaultsToMenuBarOnly() {
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let state = AppState(defaults: UserDefaults(suiteName: suiteName)!, engine: nil)
        #expect(!state.showDockIcon)
        #expect(NSApp.activationPolicy() == .accessory)
    }

    @Test func togglingShowsAndHidesTheDockIconRightAway() {
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let state = AppState(defaults: UserDefaults(suiteName: suiteName)!, engine: nil)
        state.showDockIcon = true
        #expect(NSApp.activationPolicy() == .regular)
        state.showDockIcon = false
        #expect(NSApp.activationPolicy() == .accessory)
    }

    @Test func choiceIsRemembered() {
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let defaults = UserDefaults(suiteName: suiteName)!
        AppState(defaults: defaults, engine: nil).showDockIcon = true
        #expect(AppState(defaults: defaults, engine: nil).showDockIcon)
    }
}
