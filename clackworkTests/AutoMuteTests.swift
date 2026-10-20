import Foundation
import Testing
@testable import clackwork

/// Auto-mute while the microphone is in use (FR-15, issue #16).
@MainActor
struct AutoMuteTests {
    private let suiteName = "clackworkTests.automute.\(UUID().uuidString)"
    private typealias Process = MicrophoneMonitor.Process

    private func makeState(autoMute: Bool) -> AppState {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(autoMute, forKey: "autoMuteDuringCalls")
        // A non-live monitor: whether this Mac's microphone is busy must not decide a test.
        return AppState(defaults: defaults, engine: nil, microphone: MicrophoneMonitor(live: false))
    }

    // MARK: Which processes count

    private let own = getpid()
    private let zoom = Process(pid: 500, isRunningInput: true, bundleID: "us.zoom.xos")
    private let siri = Process(pid: 766, isRunningInput: true, bundleID: "com.apple.CoreSpeech")
    private let faceTime = Process(pid: 900, isRunningInput: true, bundleID: "com.apple.FaceTime")
    /// Registered applications on this pretend system: Zoom and FaceTime, not the Siri daemon.
    private func isApp(_ pid: pid_t) -> Bool { [500, 900].contains(pid) }

    @Test func anotherAppRunningInputCounts() {
        #expect(!MicrophoneMonitor.anyRunningInput([], ownPID: own, isApp: isApp))
        #expect(!MicrophoneMonitor.anyRunningInput([Process(pid: 500, isRunningInput: false, bundleID: "us.zoom.xos")],
                                                   ownPID: own, isApp: isApp))
        #expect(MicrophoneMonitor.anyRunningInput([zoom], ownPID: own, isApp: isApp))
        #expect(MicrophoneMonitor.anyRunningInput([Process(pid: 501, isRunningInput: true, bundleID: nil)],
                                                  ownPID: own, isApp: { _ in false }),
                "a process without a bundle ID still counts")
    }

    @Test func clackworkItselfDoesNotCount() {
        let me = Process(pid: own, isRunningInput: true, bundleID: "com.surajkhamkar.clackwork")
        #expect(!MicrophoneMonitor.anyRunningInput([me], ownPID: own, isApp: { _ in true }))
    }

    @Test func appleBackgroundListenersDoNotCountButAppleAppsDo() {
        #expect(MicrophoneMonitor.isSystemListener(siri, isApp: isApp),
                "CoreSpeech listens for the wake word all the time; it must not keep the app muted")
        #expect(!MicrophoneMonitor.isSystemListener(faceTime, isApp: isApp))
        #expect(!MicrophoneMonitor.isSystemListener(zoom, isApp: { _ in false }), "only Apple processes are ever ignored")

        #expect(!MicrophoneMonitor.anyRunningInput([siri], ownPID: own, isApp: isApp))
        #expect(MicrophoneMonitor.anyRunningInput([siri, faceTime], ownPID: own, isApp: isApp))
    }

    // MARK: App behaviour

    @Test func mutesWhileTheMicrophoneIsInUseAndReturnsAfter() {
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let state = makeState(autoMute: true)
        #expect(!state.isAutoMuted)

        state.microphone.simulate(inUse: true)
        #expect(state.isAutoMuted)
        state.microphone.simulate(inUse: false)
        #expect(!state.isAutoMuted)
    }

    @Test func doesNothingWhileTheSettingIsOff() {
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let state = makeState(autoMute: false)
        state.microphone.simulate(inUse: true)
        #expect(!state.isAutoMuted)

        // Turning the setting on during a call mutes right away; off again unmutes.
        state.autoMuteDuringCalls = true
        state.microphone.simulate(inUse: true)
        #expect(state.isAutoMuted)
        state.autoMuteDuringCalls = false
        #expect(!state.isAutoMuted)
    }

    @Test func leavesTheUsersOwnMuteAlone() {
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let state = makeState(autoMute: true)
        state.mute()
        state.microphone.simulate(inUse: true)
        state.microphone.simulate(inUse: false)
        #expect(state.isMuted, "a call ending must not undo a mute the user chose")
        #expect(!state.isAutoMuted)

        state.unmute()
        state.microphone.simulate(inUse: true)
        #expect(!state.isMuted)
        #expect(state.isAutoMuted, "unmuting by hand does not override the call")
    }

    @Test func gateBlocksPlaybackWhileAutoMuted() {
        let gate = PlaybackGate()
        gate.update(isEnabled: true, isMuted: false, profileID: "mx-brown")
        #expect(gate.profileToPlay == "mx-brown")
        gate.update(isAutoMuted: true)
        #expect(gate.profileToPlay == nil)
        gate.update(isAutoMuted: false)
        #expect(gate.profileToPlay == "mx-brown")
    }

    @Test func menuBarIconShowsAutoMuteAsMuted() {
        #expect(MenuBarIcon.State(isEnabled: true, isMuted: false, isAutoMuted: true) == .muted)
        #expect(MenuBarIcon.State(isEnabled: true, isMuted: false, isAutoMuted: false) == .on)
        #expect(MenuBarIcon.State(isEnabled: false, isMuted: false, isAutoMuted: true) == .off, "off still wins")
    }

    @Test func unmutingByHandDuringACallSaysWhyItStaysSilent() {
        let content = HUDContent(after: .toggleMute, isEnabled: true, isMuted: false, isAutoMuted: true,
                                 profile: .defaultProfile, volume: 0.6, combo: ShortcutAction.toggleMute.defaultCombo)
        #expect(content.title == "Unmuted")
        #expect(content.detail == "Silent while the microphone is in use")
        #expect(content.icon == .symbol("speaker.slash.fill"))
    }

    @Test func liveMonitorAnswersWithoutCrashingOnThisMachine() {
        // The HAL may report nothing at all on a CI runner; the point is that asking is safe
        // and that stopping always ends with "not in use".
        let monitor = MicrophoneMonitor()
        monitor.start()
        monitor.refresh()
        monitor.stop()
        #expect(!monitor.isInUse)
    }
}
