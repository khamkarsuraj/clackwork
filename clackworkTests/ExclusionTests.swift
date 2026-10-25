import Foundation
import Testing
@testable import clackwork

/// Per-app exclusion list (FR-16, issue #17).
@MainActor
struct ExclusionTests {
    private let suiteName = "clackworkTests.exclusions.\(UUID().uuidString)"
    private var defaults: UserDefaults { UserDefaults(suiteName: suiteName)! }

    private let zoom = ExcludedApp(bundleID: "us.zoom.xos", name: "zoom.us")
    private let terminal = ExcludedApp(bundleID: "com.apple.Terminal", name: "Terminal")

    /// An AppState whose idea of the frontmost app is whatever the test says.
    private func makeState(front: @escaping () -> String?, exclusions: ExclusionStore) -> AppState {
        AppState(defaults: defaults, engine: nil, microphone: MicrophoneMonitor(live: false),
                 exclusions: exclusions, frontmostBundleID: front)
    }

    // MARK: The list

    @Test func addsWithoutDuplicatesRemovesAndPersists() {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ExclusionStore(defaults: defaults)
        #expect(store.apps.isEmpty)
        store.add(zoom)
        store.add(zoom)
        store.add(terminal)
        #expect(store.apps == [zoom, terminal])
        #expect(store.contains(bundleID: zoom.bundleID))

        store.remove(zoom)
        #expect(store.apps == [terminal])

        let reloaded = ExclusionStore(defaults: defaults)
        #expect(reloaded.apps == [terminal], "the list survives a relaunch")
    }

    @Test func readsAnAppBundle() throws {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let app = try #require(ExcludedApp(url: url))
        #expect(app.bundleID == "com.apple.Terminal")
        #expect(app.name == "Terminal")
        #expect(ExcludedApp(url: URL(fileURLWithPath: "/usr/bin")) == nil, "not an app bundle")
    }

    // MARK: Pausing

    @Test func pausesWhileAnExcludedAppIsInFrontAndResumesAfter() {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ExclusionStore(defaults: defaults)
        store.add(zoom)
        var front: String? = "com.apple.Safari"
        let state = makeState(front: { front }, exclusions: store)
        #expect(state.excludedAppInFront == nil)

        front = zoom.bundleID
        state.frontmostAppChanged(bundleID: front)
        #expect(state.excludedAppInFront == zoom)

        front = "com.apple.Safari"
        state.frontmostAppChanged(bundleID: front)
        #expect(state.excludedAppInFront == nil)
    }

    @Test func noticesTheAppAlreadyInFrontAtLaunch() {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ExclusionStore(defaults: defaults)
        store.add(terminal)
        let state = makeState(front: { self.terminal.bundleID }, exclusions: store)
        #expect(state.excludedAppInFront == terminal)
    }

    @Test func editingTheListAppliesToTheAppInFrontAtOnce() {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ExclusionStore(defaults: defaults)
        let state = makeState(front: { self.zoom.bundleID }, exclusions: store)
        #expect(state.excludedAppInFront == nil)

        store.add(zoom)
        #expect(state.excludedAppInFront == zoom, "adding the current app pauses right away")
        store.remove(zoom)
        #expect(state.excludedAppInFront == nil, "removing it resumes right away")
    }

    @Test func gateBlocksPlaybackWhilePaused() {
        let gate = PlaybackGate()
        gate.update(isEnabled: true, isMuted: false, profileID: "walnut-bump")
        gate.update(isExcludedAppInFront: true)
        #expect(gate.profileToPlay == nil)
        gate.update(isExcludedAppInFront: false)
        #expect(gate.profileToPlay == "walnut-bump")
    }

    @Test func independentOfMute() {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ExclusionStore(defaults: defaults)
        store.add(zoom)
        let state = makeState(front: { self.zoom.bundleID }, exclusions: store)
        state.mute()
        state.frontmostAppChanged(bundleID: "com.apple.Safari")
        #expect(state.isMuted, "leaving the excluded app does not unmute")
        state.unmute()
        state.frontmostAppChanged(bundleID: zoom.bundleID)
        #expect(state.excludedAppInFront == zoom, "unmuting does not override the exclusion")
    }

    @Test func clackworkComingToTheFrontDoesNotCountAsLeavingTheApp() throws {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ExclusionStore(defaults: defaults)
        store.add(zoom)
        let state = makeState(front: { self.zoom.bundleID }, exclusions: store)
        #expect(state.excludedAppInFront == zoom)

        // Opening the popover or the window activates Clackwork; the user is still "in" Zoom.
        let own = try #require(Bundle.main.bundleIdentifier)
        state.frontmostAppChanged(bundleID: own)
        #expect(state.excludedAppInFront == zoom, "the popover keeps showing why sound is paused")
    }

    @Test func menuBarIconShowsPausedWithTheMutedGlyphAndItsOwnDescription() {
        let paused = MenuBarIcon.State(isEnabled: true, isMuted: false, isPausedForApp: true)
        #expect(paused == .paused)
        #expect(paused.showsSlash)
        #expect(paused.accessibilityDescription == "Clackwork, paused for the app in front")
        #expect(MenuBarIcon.State(isEnabled: true, isMuted: true, isPausedForApp: true) == .muted, "a mute wins in the description")
        #expect(MenuBarIcon.State(isEnabled: false, isMuted: false, isPausedForApp: true) == .off)
    }
}
