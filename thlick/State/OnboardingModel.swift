import Combine
import Foundation

/// Where the first-launch onboarding is, and what each button does (FR-20 to FR-24).
///
/// The permission step is skipped when Input Monitoring is already allowed, and leaves on
/// its own as soon as the app sees the grant (FR-22). macOS can hold a grant back until
/// the app restarts, so the step also offers Quit & Reopen. From the permission step on,
/// the rest can be skipped.
final class OnboardingModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome, permission, keyboard, finish
    }

    @Published private(set) var step: Step = .welcome

    private let appState: AppState
    /// Registers or removes the login item. Replaced in tests, which must not touch the real one.
    private let setLaunchAtLogin: (Bool) -> Void
    private var subscription: AnyCancellable?

    init(appState: AppState, setLaunchAtLogin: ((Bool) -> Void)? = nil) {
        self.appState = appState
        self.setLaunchAtLogin = setLaunchAtLogin ?? { [weak appState] in appState?.launchAtLogin = $0 }
        // @Published emits before the property is written, so use the emitted value.
        subscription = appState.$hasInputMonitoringAccess
            .sink { [weak self] granted in
                if granted, self?.step == .permission { self?.step = .keyboard }
            }
    }

    /// Whether "Skip setup" is offered: once the user has seen why the permission is needed.
    var canSkip: Bool { step == .permission || step == .keyboard }

    func next() {
        switch step {
        case .welcome: step = appState.hasInputMonitoringAccess ? .keyboard : .permission
        case .permission, .keyboard: step = .finish
        case .finish: finish()
        }
    }

    /// Back from the keyboard step goes past the permission step, which has nothing left to do.
    func back() {
        switch step {
        case .welcome: break
        case .permission: step = .welcome
        case .keyboard: step = appState.hasInputMonitoringAccess ? .welcome : .permission
        case .finish: step = .keyboard
        }
    }

    /// "Open System Settings" on the permission step. The step moves on once access is granted.
    func requestAccess() {
        appState.requestInputMonitoringAccess()
    }

    /// "Quit & Reopen" on the permission step, for a grant that needs a restart to take
    /// effect. The new copy starts onboarding again, and goes past this step.
    func relaunch() {
        appState.relaunch()
    }

    func skip() {
        finish()
    }

    /// Ends onboarding for good, finished or skipped, and turns on the login item, which is
    /// on by default (FR-20); Settings can turn it off.
    private func finish() {
        setLaunchAtLogin(true)
        appState.hasCompletedOnboarding = true
    }
}
