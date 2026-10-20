import os

/// A thread-safe copy of the state that decides whether a key makes a sound.
///
/// `AppState` lives on the main thread; the key listener plays sounds on its own thread
/// so a busy UI can never delay a key (issue #32). This gate is what the listener reads.
nonisolated final class PlaybackGate: Sendable {
    private struct State {
        var isEnabled = true
        var isMuted = false
        /// Muted on the app's own initiative while the microphone is in use (FR-15).
        var isAutoMuted = false
        var profileID = ""
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func update(isEnabled: Bool? = nil, isMuted: Bool? = nil, isAutoMuted: Bool? = nil, profileID: String? = nil) {
        state.withLock {
            if let isEnabled { $0.isEnabled = isEnabled }
            if let isMuted { $0.isMuted = isMuted }
            if let isAutoMuted { $0.isAutoMuted = isAutoMuted }
            if let profileID { $0.profileID = profileID }
        }
    }

    /// The profile to play, or nil when sound is off or muted, by the user or automatically.
    var profileToPlay: String? {
        state.withLock { $0.isEnabled && !$0.isMuted && !$0.isAutoMuted ? $0.profileID : nil }
    }
}
