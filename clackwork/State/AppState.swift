import AppKit
import Combine
import ServiceManagement
import SwiftUI

/// App-wide settings. Every change applies immediately and is persisted (FR-11, FR-18).
final class AppState: ObservableObject {
    private enum Key {
        static let enabled = "isEnabled"
        static let profile = "selectedProfileID"
        static let volume = "volume"
        static let showDockIcon = "showDockIcon"
        static let showHUD = "showHUD"
        static let autoMute = "autoMuteDuringCalls"
        static let onboarding = "hasCompletedOnboarding"
    }

    // MARK: Sound

    /// Whether key listening is on at all (FR-12).
    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Key.enabled)
            gate.update(isEnabled: isEnabled)
            updateListener()
        }
    }

    /// The active keyboard profile (FR-8).
    @Published var selectedProfile: KeyboardProfile {
        didSet {
            defaults.set(selectedProfile.id, forKey: Key.profile)
            gate.update(profileID: selectedProfile.id)
        }
    }

    /// Master volume, 0...1, independent of system volume (FR-10).
    @Published var volume: Double {
        didSet {
            defaults.set(volume, forKey: Key.volume)
            engine?.volume = Float(volume)
        }
    }

    // MARK: General settings

    /// Start Clackwork at login (FR-20). Backed by SMAppService, so it reflects the real system state.
    @Published var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin() }
    }

    /// Off keeps Clackwork in the menu bar only (FR-19).
    @Published var showDockIcon: Bool {
        didSet {
            defaults.set(showDockIcon, forKey: Key.showDockIcon)
            applyDockIcon()
        }
    }

    /// Briefly show what a shortcut changed, like the system volume overlay.
    @Published var showHUD: Bool {
        didSet { defaults.set(showHUD, forKey: Key.showHUD) }
    }

    /// False until the first-launch onboarding is finished or skipped (FR-21 to FR-24).
    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.onboarding) }
    }

    // MARK: Sound settings (stored now, used by the engine in a later step)

    /// Stay silent while any app uses the microphone (FR-15).
    @Published var autoMuteDuringCalls: Bool {
        didSet {
            defaults.set(autoMuteDuringCalls, forKey: Key.autoMute)
            applyAutoMuteSetting()
        }
    }

    // MARK: Per-app exclusions (FR-16)

    /// The excluded app that is in front right now, or nil. Sound pauses while it is set.
    @Published private(set) var excludedAppInFront: ExcludedApp? {
        didSet { gate.update(isExcludedAppInFront: excludedAppInFront != nil) }
    }
    let exclusions: ExclusionStore
    /// The frontmost app's bundle ID. Injected so tests can stand in for app switches.
    private let frontmostBundleID: () -> String?
    private var appSwitchObserver: NSObjectProtocol?

    // MARK: Auto-mute (FR-15)

    /// Muted by the app itself because the microphone is in use. Separate from `isMuted`,
    /// so a call ending never undoes a mute the user chose, and vice versa.
    @Published private(set) var isAutoMuted = false {
        didSet { gate.update(isAutoMuted: isAutoMuted) }
    }
    /// Watches the microphone only while the setting is on.
    let microphone: MicrophoneMonitor

    // MARK: Mute (FR-13): the app keeps running but stays silent. Not persisted across launches.

    @Published private(set) var isMuted = false {
        didSet { gate.update(isMuted: isMuted) }
    }

    /// When a timed mute ends, or nil for "until I unmute".
    @Published private(set) var muteEndsAt: Date?
    /// The length the current timed mute was started with, or nil for "until I unmute".
    @Published private(set) var muteDuration: TimeInterval?
    private var muteTimer: Timer?

    /// Whether macOS currently allows this app to listen to key events (Input Monitoring).
    @Published private(set) var hasInputMonitoringAccess: Bool

    /// True while the system-wide key tap is active.
    @Published private(set) var isListening = false

    /// Every key down and up seen by the listener, for the on-screen keyboard animation.
    let keyEvents = PassthroughSubject<KeyEvent, Never>()

    let engine: SoundEngine?
    private var listener: KeyListener!
    /// What the listener thread reads to decide whether a key plays; mirrors the state above.
    private let gate = PlaybackGate()
    private var permissionPoll: Timer?
    private var activationObserver: NSObjectProtocol?
    private var subscriptions: Set<AnyCancellable> = []
    private let defaults: UserDefaults
    /// Whether macOS grants Input Monitoring right now. Injected so tests can flip it.
    private let permissionCheck: () -> Bool

    /// Pass `engine: nil` for previews and tests that should stay silent, and
    /// `microphone: MicrophoneMonitor(live: false)` for tests that must not read the HAL.
    init(defaults: UserDefaults = .standard, engine: SoundEngine? = SoundEngine(),
         permissionCheck: @escaping () -> Bool = { KeyListener.hasAccess },
         microphone: MicrophoneMonitor = MicrophoneMonitor(),
         exclusions: ExclusionStore? = nil,
         frontmostBundleID: @escaping () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }) {
        self.defaults = defaults
        self.engine = engine
        self.permissionCheck = permissionCheck
        self.microphone = microphone
        // Same defaults as the rest of the state, so a test suite never sees the real list.
        self.exclusions = exclusions ?? ExclusionStore(defaults: defaults)
        self.frontmostBundleID = frontmostBundleID
        isEnabled = defaults.object(forKey: Key.enabled) as? Bool ?? true
        let savedID = defaults.string(forKey: Key.profile)
        selectedProfile = KeyboardProfile.all.first { $0.id == savedID } ?? .defaultProfile
        volume = defaults.object(forKey: Key.volume) as? Double ?? 0.7

        launchAtLogin = SMAppService.mainApp.status == .enabled
        // Off by default: the menu bar item is how Clackwork is reached.
        showDockIcon = defaults.object(forKey: Key.showDockIcon) as? Bool ?? false
        showHUD = defaults.object(forKey: Key.showHUD) as? Bool ?? true
        hasCompletedOnboarding = defaults.bool(forKey: Key.onboarding)
        autoMuteDuringCalls = defaults.object(forKey: Key.autoMute) as? Bool ?? false
        hasInputMonitoringAccess = permissionCheck()

        engine?.volume = Float(volume)
        applyDockIcon()

        gate.update(isEnabled: isEnabled, isMuted: isMuted, profileID: selectedProfile.id)

        // @Published emits before the property is written, so use the emitted value.
        microphone.$isInUse
            .dropFirst()
            .sink { [weak self] inUse in self?.updateAutoMute(microphoneInUse: inUse) }
            .store(in: &subscriptions)
        applyAutoMuteSetting()

        // Which app is in front: told by the system on every switch, and re-checked when
        // the list changes so adding the current app takes effect at once.
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.frontmostAppChanged(bundleID: app?.bundleIdentifier) }
        }
        // @Published emits before the property is written, so match against the emitted list.
        self.exclusions.$apps
            .dropFirst()
            .sink { [weak self] apps in
                guard let self else { return }
                self.updateExcludedApp(bundleID: self.frontmostBundleID(), in: apps)
            }
            .store(in: &subscriptions)
        frontmostAppChanged(bundleID: frontmostBundleID())

        // Sound is played on the listener thread; only the UI update hops to the main thread.
        let gate = gate
        let probe = LatencyProbe.isEnabled ? LatencyProbe() : nil
        let cpuProbe = CPUProbe.isEnabled ? CPUProbe() : nil
        listener = KeyListener(
            onKeyDown: { [engine] event in
                cpuProbe?.keyPressed()
                guard let engine, let profileID = gate.profileToPlay else { return }
                engine.play(event.type, profileID: profileID)
                probe?.record(eventNanos: event.eventNanos, tapNanos: event.tapNanos,
                              scheduledNanos: LatencyProbe.now(), audioPathMs: engine.audioPathLatencyMs)
            },
            onEvent: { [weak self] event in
                self?.keyEvents.send(event)
            }
        )
        updateListener()
        StartupProbe.mark(
            isListening ? "listener on"
                : !isEnabled ? "listener off (sound is turned off)"
                : "listener waiting for Input Monitoring"
        )

        // Permission and the login item can both be changed in System Settings while the
        // app runs; re-check whenever the user comes back to the app.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshPermissionStatus()
                self?.refreshLaunchAtLogin()
            }
        }
    }

    deinit {
        permissionPoll?.invalidate()
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        if let appSwitchObserver { NSWorkspace.shared.notificationCenter.removeObserver(appSwitchObserver) }
    }

    /// Plays the current profile's sound for a key, if sound is enabled and not muted.
    func play(_ key: KeyType) {
        guard isEnabled, !isMuted, !isAutoMuted, excludedAppInFront == nil else { return }
        engine?.play(key, profile: selectedProfile)
    }

    // MARK: Per-app exclusions

    /// Called on every app switch; tests call it to stand in for one. Clackwork coming to
    /// the front (the popover opening, the window being used) doesn't count: the user is
    /// still "in" the app they came from, and the popover must keep showing why it's paused.
    func frontmostAppChanged(bundleID: String?) {
        guard bundleID != Bundle.main.bundleIdentifier else { return }
        updateExcludedApp(bundleID: bundleID, in: exclusions.apps)
    }

    private func updateExcludedApp(bundleID: String?, in apps: [ExcludedApp]) {
        let next = bundleID.flatMap { id in apps.first { $0.bundleID == id } }
        if next != excludedAppInFront { excludedAppInFront = next }
    }

    // MARK: Auto-mute

    private func applyAutoMuteSetting() {
        if autoMuteDuringCalls {
            microphone.start()
        } else {
            microphone.stop()
        }
        updateAutoMute(microphoneInUse: microphone.isInUse)
    }

    private func updateAutoMute(microphoneInUse: Bool) {
        let next = autoMuteDuringCalls && microphoneInUse
        if next != isAutoMuted { isAutoMuted = next }
    }

    // MARK: Shortcut actions

    func mute(for duration: TimeInterval? = nil) {
        muteTimer?.invalidate()
        isMuted = true
        muteDuration = duration
        if let duration {
            muteEndsAt = Date().addingTimeInterval(duration)
            muteTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.unmute() }
            }
        } else {
            muteEndsAt = nil
        }
    }

    func unmute() {
        muteTimer?.invalidate()
        muteTimer = nil
        muteEndsAt = nil
        muteDuration = nil
        isMuted = false
    }

    func toggleMute() {
        isMuted ? unmute() : mute()
    }

    /// Moves to the next (+1) or previous (-1) profile, wrapping around, and plays a key as feedback.
    func selectKeyboard(offset: Int) {
        let all = KeyboardProfile.all
        guard let index = all.firstIndex(of: selectedProfile) else { return }
        selectedProfile = all[(index + offset + all.count) % all.count]
        play(.standard)
    }

    /// Changes the volume in steps, clamped to 0...1, and plays a key so the new level is audible.
    func adjustVolume(by delta: Double) {
        volume = min(max(volume + delta, 0), 1)
        play(.standard)
    }

    /// Re-reads the Input Monitoring permission and starts or stops the listener to match.
    func refreshPermissionStatus() {
        let granted = permissionCheck()
        if granted != hasInputMonitoringAccess { hasInputMonitoringAccess = granted }
        updateListener()
    }

    /// Asks macOS for Input Monitoring and opens the matching System Settings pane (FR-21).
    func requestInputMonitoringAccess() {
        KeyListener.requestAccess()
        openInputMonitoringSettings()
        refreshPermissionStatus()
    }

    /// Opens the Input Monitoring pane of System Settings.
    func openInputMonitoringSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }

    /// Starts a fresh copy of Clackwork and quits this one. A grant made in System Settings
    /// can stay out of reach until the app restarts, if the user picked "Later" on the
    /// system's "Quit & Reopen" prompt. Hot keys are registered non-exclusively, so the two
    /// copies overlapping for a moment doesn't cost the new one its shortcuts.
    func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error {
                    NSLog("Relaunch failed: \(error)")
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    // MARK: Listener lifecycle

    /// The tap runs only while sound is enabled and permission is granted. While sound is
    /// enabled the permission is re-checked on a timer (see `permissionPollInterval`).
    private func updateListener() {
        if isEnabled && hasInputMonitoringAccess {
            if !listener.isRunning, !listener.start() {
                // Creating the tap can fail right after permission changes; treat as not granted.
                hasInputMonitoringAccess = false
            }
        } else {
            listener.stop()
        }
        isListening = listener.isRunning
        schedulePermissionPoll()
    }

    /// How often to re-check Input Monitoring, or nil when there is no need.
    ///
    /// Waiting for permission, the check is quick so the app picks up a grant right after
    /// the user flips the switch (FR-22). While listening it is slower, enough to notice a
    /// revoke in System Settings and stop the tap without a relaunch (issue #41); the
    /// check is a single call, so this costs nothing noticeable.
    static func permissionPollInterval(isEnabled: Bool, hasAccess: Bool) -> TimeInterval? {
        guard isEnabled else { return nil }
        return hasAccess ? 5 : 2
    }

    private func schedulePermissionPoll() {
        let interval = Self.permissionPollInterval(isEnabled: isEnabled, hasAccess: hasInputMonitoringAccess)
        guard interval != permissionPoll?.timeInterval else { return }
        permissionPoll?.invalidate()
        permissionPoll = nil
        guard let interval else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissionStatus() }
        }
        // Lets the system batch this wake-up with others; exact timing doesn't matter here.
        timer.tolerance = interval * 0.2
        permissionPoll = timer
    }

    /// The interval of the running permission check, for tests.
    var permissionPollInterval: TimeInterval? { permissionPoll?.timeInterval }

    /// Re-reads the login item, which the user can remove in System Settings › General ›
    /// Login Items (FR-20). Setting the matching value makes `applyLaunchAtLogin` a no-op.
    func refreshLaunchAtLogin() {
        let current = SMAppService.mainApp.status == .enabled
        if current != launchAtLogin { launchAtLogin = current }
    }

    private func applyLaunchAtLogin() {
        let current = SMAppService.mainApp.status == .enabled
        // Also stops the reset below from re-entering this method.
        guard launchAtLogin != current else { return }
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Launch at login change failed: \(error)")
            launchAtLogin = current
        }
    }

    private func applyDockIcon() {
        NSApp?.setActivationPolicy(showDockIcon ? .regular : .accessory)
        if !showDockIcon { NSApp?.activate(ignoringOtherApps: true) }
    }
}
