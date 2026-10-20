import Foundation
import Testing
@testable import clackwork

/// Input Monitoring changes are picked up without a relaunch (FR-22, issue #41).
///
/// Starting the tap needs the real permission, so the tests that listen run only where
/// the test host has it; the rest run everywhere.
@MainActor
struct PermissionTests {
    private let suiteName = "clackworkTests.permission.\(UUID().uuidString)"

    @Test func pollsQuicklyWhileWaitingAndSlowlyWhileListening() {
        #expect(AppState.permissionPollInterval(isEnabled: true, hasAccess: false) == 2)
        #expect(AppState.permissionPollInterval(isEnabled: true, hasAccess: true) == 5)
        #expect(AppState.permissionPollInterval(isEnabled: false, hasAccess: false) == nil)
        #expect(AppState.permissionPollInterval(isEnabled: false, hasAccess: true) == nil)
    }

    @Test func checksOnlyWhileSoundIsOn() {
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let state = AppState(defaults: UserDefaults(suiteName: suiteName)!, engine: nil,
                             permissionCheck: { false })
        #expect(state.permissionPollInterval == 2, "waiting for permission")
        state.isEnabled = false
        #expect(state.permissionPollInterval == nil, "nothing to check while sound is off")
        state.isEnabled = true
        #expect(state.permissionPollInterval == 2)
    }

    @Test func revokingStopsTheListenerAndShowsItAsMissing() {
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        guard KeyListener.hasAccess else { return }
        var granted = true
        let state = AppState(defaults: UserDefaults(suiteName: suiteName)!, engine: nil,
                             permissionCheck: { granted })
        #expect(state.isListening)
        #expect(state.permissionPollInterval == 5, "listening: the slow check")

        granted = false
        state.refreshPermissionStatus()
        #expect(!state.hasInputMonitoringAccess)
        #expect(!state.isListening)
        #expect(state.permissionPollInterval == 2, "back to waiting for permission")
        state.isEnabled = false
    }

    @Test func grantingStartsTheListenerWithoutARelaunch() {
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        guard KeyListener.hasAccess else { return }
        var granted = false
        let state = AppState(defaults: UserDefaults(suiteName: suiteName)!, engine: nil,
                             permissionCheck: { granted })
        #expect(!state.hasInputMonitoringAccess)
        #expect(!state.isListening)

        granted = true
        state.refreshPermissionStatus()
        #expect(state.hasInputMonitoringAccess)
        #expect(state.isListening)
        #expect(state.permissionPollInterval == 5)
        state.isEnabled = false
    }
}
