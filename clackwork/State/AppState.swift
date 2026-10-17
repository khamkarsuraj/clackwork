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
        static let stereo = "stereoPositioning"
        static let autoMute = "autoMuteDuringCalls"
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

    // MARK: Sound settings (stored now, used by the engine in a later step)

    @Published var stereoPositioning: Bool {
        didSet { defaults.set(stereoPositioning, forKey: Key.stereo) }
    }

    @Published var autoMuteDuringCalls: Bool {
        didSet { defaults.set(autoMuteDuringCalls, forKey: Key.autoMute) }
    }

    // MARK: Mute (FR-13): the app keeps running but stays silent. Not persisted across launches.

    @Published private(set) var isMuted = false {
        didSet { gate.update(isMuted: isMuted) }
    }

    /// When a timed mute ends, or nil for "until I unmute".
    @Published private(set) var muteEndsAt: Date?
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
    private let defaults: UserDefaults

    /// Pass `engine: nil` for previews and tests that should stay silent.
    init(defaults: UserDefaults = .standard, engine: SoundEngine? = SoundEngine()) {
        self.defaults = defaults
        self.engine = engine
        isEnabled = defaults.object(forKey: Key.enabled) as? Bool ?? true
        let savedID = defaults.string(forKey: Key.profile)
        selectedProfile = KeyboardProfile.all.first { $0.id == savedID } ?? .defaultProfile
        volume = defaults.object(forKey: Key.volume) as? Double ?? 0.7

        launchAtLogin = SMAppService.mainApp.status == .enabled
        // Default stays on until the menu bar item exists; the design's default is off.
        showDockIcon = defaults.object(forKey: Key.showDockIcon) as? Bool ?? true
        stereoPositioning = defaults.object(forKey: Key.stereo) as? Bool ?? false
        autoMuteDuringCalls = defaults.object(forKey: Key.autoMute) as? Bool ?? false
        hasInputMonitoringAccess = KeyListener.hasAccess

        engine?.volume = Float(volume)
        applyDockIcon()

        gate.update(isEnabled: isEnabled, isMuted: isMuted, profileID: selectedProfile.id)

        // Sound is played on the listener thread; only the UI update hops to the main thread.
        let gate = gate
        let probe = LatencyProbe.isEnabled ? LatencyProbe() : nil
        listener = KeyListener(
            onKeyDown: { [engine] event in
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

        // Permission can be granted or revoked in System Settings while the app runs;
        // re-check whenever the user comes back to the app.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissionStatus() }
        }
    }

    /// Plays the current profile's sound for a key, if sound is enabled and not muted.
    func play(_ key: KeyType) {
        guard isEnabled, !isMuted else { return }
        engine?.play(key, profile: selectedProfile)
    }

    // MARK: Shortcut actions

    func mute(for duration: TimeInterval? = nil) {
        muteTimer?.invalidate()
        isMuted = true
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
        let granted = KeyListener.hasAccess
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

    // MARK: Listener lifecycle

    /// The tap runs only while sound is enabled and permission is granted. While enabled but
    /// waiting for permission, the status is polled so the app continues on its own once
    /// access is granted (FR-22).
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

        let shouldPoll = isEnabled && !hasInputMonitoringAccess
        if shouldPoll, permissionPoll == nil {
            permissionPoll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshPermissionStatus() }
            }
        } else if !shouldPoll {
            permissionPoll?.invalidate()
            permissionPoll = nil
        }
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
