import AppKit

/// Which keys the on-screen keyboard draws as pressed.
///
/// Deliberately not observable. Changes go straight to the illustration's layers through
/// `onChange`, so a key press never triggers a SwiftUI update or a window layout pass
/// (issue #33: routing presses through SwiftUI cost 10-30% CPU while typing).
final class KeyPressAnimator {
    private(set) var pressedKeys: Set<KeyboardIllustration.KeyID> = [] {
        didSet { if pressedKeys != oldValue { onChange?(pressedKeys) } }
    }

    /// Set by the illustration's layer view; called on every change to `pressedKeys`.
    var onChange: ((Set<KeyboardIllustration.KeyID>) -> Void)?

    private var releaseTasks: [KeyboardIllustration.KeyID: Task<Void, Never>] = [:]
    private var occlusionObserver: NSObjectProtocol?

    init() {
        // Key-ups are skipped while the app can't be seen, so start clean when it can be again.
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeOcclusionStateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !Self.isAppVisible else { return }
                self.clear()
            }
        }
    }

    deinit {
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
    }

    /// Real keys: sink on key down, pop up on key up. Skipped while no window is visible
    /// (minimized, hidden or covered), since nobody would see the animation.
    func handle(_ event: KeyEvent, reduceMotion: Bool) {
        guard let location = event.location, Self.isAppVisible else { return }
        releaseTasks[location]?.cancel()
        releaseTasks[location] = nil
        if reduceMotion { return }
        if event.isDown {
            pressedKeys.insert(location)
        } else {
            pressedKeys.remove(location)
        }
    }

    /// Sinks a key for a moment. Used for mouse-driven sounds (cards, Preview) and for the
    /// test field when the system-wide listener isn't running.
    func press(_ key: KeyboardIllustration.KeyID, reduceMotion: Bool) {
        guard !reduceMotion else { return }
        releaseTasks[key]?.cancel()
        pressedKeys.insert(key)
        releaseTasks[key] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled, let self else { return }
            pressedKeys.remove(key)
            releaseTasks[key] = nil
        }
    }

    func clear() {
        releaseTasks.values.forEach { $0.cancel() }
        releaseTasks.removeAll()
        if !pressedKeys.isEmpty { pressedKeys.removeAll() }
    }

    private static var isAppVisible: Bool { NSApp.occlusionState.contains(.visible) }
}
