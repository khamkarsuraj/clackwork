import Foundation
import Testing
@testable import clackwork

/// Menu bar popover: the timed-mute state it shows and the countdown text.
@MainActor
struct PopoverTests {
    private let suiteName = "clackworkTests.popover.\(UUID().uuidString)"

    private func makeState() -> AppState {
        AppState(defaults: UserDefaults(suiteName: suiteName)!, engine: nil)
    }

    @Test func timedMuteRemembersItsDuration() {
        let state = makeState()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        state.mute(for: 15 * 60)
        #expect(state.isMuted)
        #expect(state.muteDuration == TimeInterval(15 * 60))
        #expect(state.muteEndsAt != nil)

        state.mute()
        #expect(state.muteDuration == nil)
        #expect(state.muteEndsAt == nil)

        state.mute(for: 60 * 60)
        state.unmute()
        #expect(!state.isMuted)
        #expect(state.muteDuration == nil)
    }

    @Test func timedMuteEndsByItself() async throws {
        let state = makeState()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        state.mute(for: 0.1)
        #expect(state.isMuted)
        // The main run loop keeps running while this test is suspended, so the timer fires.
        try await waitUntil { !state.isMuted }
        #expect(!state.isMuted)
        #expect(state.muteEndsAt == nil)
        #expect(state.muteDuration == nil)
    }

    @Test func remainingRoundsUpToTheMinute() {
        let now = Date()
        #expect(PopoverView.remaining(until: now.addingTimeInterval(14 * 60 + 1), from: now) == "15 min")
        #expect(PopoverView.remaining(until: now.addingTimeInterval(14 * 60), from: now) == "14 min")
        #expect(PopoverView.remaining(until: now.addingTimeInterval(60 * 60), from: now) == "1 hr")
        // Never shows "0 min" in the last seconds before the mute ends.
        #expect(PopoverView.remaining(until: now.addingTimeInterval(5), from: now) == "1 min")
        #expect(PopoverView.remaining(until: now.addingTimeInterval(-5), from: now) == "1 min")
    }
}
