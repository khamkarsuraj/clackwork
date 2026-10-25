import Foundation
import Testing
@testable import clackwork

/// First-launch onboarding (FR-20 to FR-24, issues #21 to #25).
///
/// Sound is off in every test, so no real key tap starts; permission is stubbed and the
/// login item is recorded instead of registered.
@MainActor
struct OnboardingTests {
    private let suiteName = "clackworkTests.onboarding.\(UUID().uuidString)"

    /// What the stubbed permission check answers; flipped by the tests.
    private final class Permission {
        var granted: Bool
        init(granted: Bool) { self.granted = granted }
    }

    @MainActor
    private final class Harness {
        let permission: Permission
        var loginItem: [Bool] = []
        let defaults: UserDefaults
        let state: AppState
        lazy var model = OnboardingModel(appState: state, setLaunchAtLogin: { [unowned self] in loginItem.append($0) })

        var granted: Bool {
            get { permission.granted }
            set { permission.granted = newValue }
        }

        init(suiteName: String, granted: Bool) {
            let permission = Permission(granted: granted)
            self.permission = permission
            defaults = UserDefaults(suiteName: suiteName)!
            defaults.set(false, forKey: "isEnabled")
            state = AppState(defaults: defaults, engine: nil, permissionCheck: { permission.granted },
                             microphone: MicrophoneMonitor(live: false), frontmostBundleID: { nil })
        }
    }

    @Test func showsUntilFinished() {
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let harness = Harness(suiteName: suiteName, granted: true)
        #expect(!harness.state.hasCompletedOnboarding)
        harness.model.next()
        harness.model.next()
        harness.model.next()
        #expect(harness.model.step == .finish)
        harness.model.next()
        #expect(harness.state.hasCompletedOnboarding)

        let relaunched = AppState(defaults: harness.defaults, engine: nil, permissionCheck: { true },
                                  microphone: MicrophoneMonitor(live: false), frontmostBundleID: { nil })
        #expect(relaunched.hasCompletedOnboarding, "not shown again")
    }

    @Test func asksForPermissionOnlyWhenMissing() {
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let missing = Harness(suiteName: suiteName, granted: false)
        missing.model.next()
        #expect(missing.model.step == .permission)

        let allowed = Harness(suiteName: suiteName, granted: true)
        allowed.model.next()
        #expect(allowed.model.step == .keyboard, "nothing to ask for")
    }

    @Test func grantingMovesOnWithoutARelaunch() {
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let harness = Harness(suiteName: suiteName, granted: false)
        harness.model.next()
        #expect(harness.model.step == .permission)

        harness.granted = true
        harness.state.refreshPermissionStatus()
        #expect(harness.model.step == .keyboard)
    }

    @Test func grantingOnAnotherStepDoesNotJump() {
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let harness = Harness(suiteName: suiteName, granted: false)
        harness.granted = true
        harness.state.refreshPermissionStatus()
        #expect(harness.model.step == .welcome)
    }

    @Test func backSkipsAPermissionStepThatIsDone() {
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let harness = Harness(suiteName: suiteName, granted: false)
        harness.model.next()
        harness.model.back()
        #expect(harness.model.step == .welcome)

        harness.model.next()
        harness.granted = true
        harness.state.refreshPermissionStatus()
        harness.model.next()
        #expect(harness.model.step == .finish)
        harness.model.back()
        #expect(harness.model.step == .keyboard)
        harness.model.back()
        #expect(harness.model.step == .welcome, "the permission step has nothing left to do")
    }

    @Test func canBeSkippedFromThePermissionStepOn() {
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let harness = Harness(suiteName: suiteName, granted: false)
        #expect(!harness.model.canSkip, "welcome")
        harness.model.next()
        #expect(harness.model.canSkip, "permission")
        harness.granted = true
        harness.state.refreshPermissionStatus()
        #expect(harness.model.canSkip, "keyboard")
        harness.model.next()
        #expect(!harness.model.canSkip, "finish: the last button is right there")
    }

    @Test func skippingFinishesWithTheLoginItemOn() {
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let harness = Harness(suiteName: suiteName, granted: false)
        harness.model.next()
        harness.model.skip()
        #expect(harness.state.hasCompletedOnboarding)
        #expect(harness.loginItem == [true])
    }

    @Test func finishingTurnsOnTheLoginItem() {
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let harness = Harness(suiteName: suiteName, granted: true)
        harness.model.next()
        harness.model.next()
        #expect(harness.loginItem.isEmpty, "not before the last step")
        harness.model.next()
        #expect(harness.loginItem == [true])
        #expect(harness.state.hasCompletedOnboarding)
    }
}
