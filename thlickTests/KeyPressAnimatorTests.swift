import AppKit
import Testing
@testable import thlick

/// Issue #33: which keys the on-screen keyboard draws as pressed, kept out of SwiftUI.
@MainActor
struct KeyPressAnimatorTests {
    private let q = KeyboardLayout.Location(row: 1, column: 1)

    private func event(_ location: KeyboardLayout.Location?, down: Bool) -> KeyEvent {
        KeyEvent(type: .standard, isDown: down, location: location)
    }

    @Test func keyDownSinksAndKeyUpRaises() {
        let animator = KeyPressAnimator(isAppVisible: { true })
        var changes: [Set<KeyboardLayout.Location>] = []
        animator.onChange = { changes.append($0) }

        animator.handle(event(q, down: true), reduceMotion: false)
        #expect(animator.pressedKeys == [q])
        animator.handle(event(q, down: false), reduceMotion: false)
        #expect(animator.pressedKeys.isEmpty)
        #expect(changes == [[q], []])
    }

    @Test func repeatedStateDoesNotNotify() {
        let animator = KeyPressAnimator(isAppVisible: { true })
        var count = 0
        animator.onChange = { _ in count += 1 }
        animator.handle(event(q, down: true), reduceMotion: false)
        animator.handle(event(q, down: true), reduceMotion: false)
        #expect(count == 1)
    }

    @Test func ignoredWhileNoWindowIsVisible() {
        let animator = KeyPressAnimator(isAppVisible: { false })
        animator.handle(event(q, down: true), reduceMotion: false)
        #expect(animator.pressedKeys.isEmpty)
    }

    @Test func ignoresKeysNotOnTheDrawnBoard() {
        let animator = KeyPressAnimator(isAppVisible: { true })
        animator.handle(event(nil, down: true), reduceMotion: false)
        #expect(animator.pressedKeys.isEmpty)
    }

    @Test func reduceMotionKeepsKeysStill() {
        let animator = KeyPressAnimator(isAppVisible: { true })
        animator.handle(event(q, down: true), reduceMotion: true)
        animator.press(.space, reduceMotion: true)
        #expect(animator.pressedKeys.isEmpty)
    }

    @Test func pressReleasesOnItsOwn() async throws {
        let animator = KeyPressAnimator(isAppVisible: { true })
        animator.press(.space, reduceMotion: false)
        #expect(animator.pressedKeys == [.space])
        // The release is scheduled 140 ms out; wait for it rather than racing it with a sleep.
        try await waitUntil { animator.pressedKeys.isEmpty }
        #expect(animator.pressedKeys.isEmpty)
    }

    @Test func clearReleasesEverythingAndCancelsPendingReleases() async throws {
        let animator = KeyPressAnimator(isAppVisible: { true })
        animator.press(.space, reduceMotion: false)
        animator.handle(event(q, down: true), reduceMotion: false)
        animator.clear()
        #expect(animator.pressedKeys.isEmpty)

        var count = 0
        animator.onChange = { _ in count += 1 }
        try await Task.sleep(nanoseconds: 400_000_000)
        #expect(count == 0)
    }

    @Test func hidingTheAppReleasesHeldKeys() async throws {
        var visible = true
        let animator = KeyPressAnimator(isAppVisible: { visible })
        animator.handle(event(q, down: true), reduceMotion: false)

        visible = false
        NotificationCenter.default.post(name: NSApplication.didChangeOcclusionStateNotification, object: nil)
        try await waitUntil { animator.pressedKeys.isEmpty }
        #expect(animator.pressedKeys.isEmpty)
    }
}
