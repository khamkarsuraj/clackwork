import Carbon.HIToolbox
import Testing
@testable import clackwork

/// FR-2: each key code maps to the right kind of key; the drawn board finds its keys.
struct KeyHandlingTests {
    @Test(arguments: [
        (kVK_Space, KeyType.space),
        (kVK_Return, .returnKey),
        (kVK_ANSI_KeypadEnter, .returnKey),
        (kVK_Delete, .backspace),
        (kVK_ForwardDelete, .backspace),
        (kVK_Shift, .modifier),
        (kVK_RightCommand, .modifier),
        (kVK_CapsLock, .modifier),
        (kVK_Function, .modifier),
        (kVK_ANSI_A, .standard),
        (kVK_ANSI_1, .standard),
        (kVK_ANSI_Slash, .standard),
        (kVK_F5, .standard),
    ])
    func keyCodeMapsToKeyType(keyCode: Int, expected: KeyType) {
        #expect(KeyListener.keyType(for: Int64(keyCode)) == expected)
    }

    @Test func boardLocationsMatchTheLayout() {
        #expect(KeyboardLayout.location(for: kVK_Space) == .space)
        #expect(KeyboardLayout.location(for: kVK_ANSI_Q) == KeyboardLayout.Location(row: 1, column: 1))
        #expect(KeyboardLayout.location(for: kVK_Escape) == KeyboardLayout.Location(row: 0, column: 0))
        #expect(KeyboardLayout.location(for: kVK_UpArrow) == nil)
    }

    @Test func everyMappedLocationIsOnTheBoard() {
        for keyCode in 0..<128 {
            guard let location = KeyboardLayout.location(for: keyCode) else { continue }
            #expect(KeyboardLayout.rows.indices.contains(location.row))
            #expect(KeyboardLayout.rows[location.row].indices.contains(location.column))
        }
    }

    // MARK: Playback gate (FR-12, FR-13)

    @Test func gatePlaysOnlyWhenEnabledAndNotMuted() {
        let gate = PlaybackGate()
        gate.update(isEnabled: true, isMuted: false, profileID: "cobalt-clack")
        #expect(gate.profileToPlay == "cobalt-clack")
        gate.update(isMuted: true)
        #expect(gate.profileToPlay == nil)
        gate.update(isEnabled: false, isMuted: false)
        #expect(gate.profileToPlay == nil)
        gate.update(isEnabled: true, profileID: "ember-tap")
        #expect(gate.profileToPlay == "ember-tap")
    }

    // MARK: Latency probe timestamps (NFR latency)

    @Test func eventTimestampInNanosecondsIsKept() {
        let now: UInt64 = 50_000_000_000
        #expect(LatencyProbe.eventNanos(fromTimestamp: now - 2_000_000, now: now) == now - 2_000_000)
    }

    @Test func futureOrStaleTimestampFallsBackToNow() {
        let now: UInt64 = 50_000_000_000
        #expect(LatencyProbe.eventNanos(fromTimestamp: now + 1_000, now: now) == now)
        #expect(LatencyProbe.eventNanos(fromTimestamp: now - 5_000_000_000, now: now) == now)
    }
}
