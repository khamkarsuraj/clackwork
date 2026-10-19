import AppKit
import SwiftUI

/// Shows the shortcut HUD near the bottom of the screen for a moment after a shortcut
/// (PRD design principles 1 and 5), the way the system volume overlay does.
///
/// The HUD is a click-through panel that never takes focus, floats over every window
/// including full-screen apps, and follows the screen the pointer is on. Pressing a
/// shortcut while it is up updates it in place and restarts the timer.
@MainActor
final class HUDController {
    /// How long the HUD stays up after the last shortcut.
    static let displayDuration: TimeInterval = 1.2
    /// Distance from the bottom of the usable screen area.
    private static let bottomInset: CGFloat = 80

    /// What is showing, or nil while hidden.
    private(set) var content: HUDContent?
    /// Created on first use so the app pays nothing until a shortcut is pressed.
    private(set) var panel: NSPanel?
    private var hosting: NSHostingView<HUDView>?
    private var hideTimer: Timer?
    /// Bumped on every show and hide, so a fade-out finishing late can't hide a HUD
    /// that was shown again in the meantime.
    private var generation = 0
    /// Whether to skip the fades. Injected so tests can run without animation.
    private let reduceMotion: () -> Bool

    init(reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }) {
        self.reduceMotion = reduceMotion
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(_ content: HUDContent) {
        self.content = content
        let panel = panel ?? makePanel(with: content)
        hosting?.rootView = HUDView(content: content)
        generation += 1
        hideTimer?.invalidate()

        if !panel.isVisible {
            panel.setFrameOrigin(Self.origin(for: panel.frame.size))
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        fade(panel, to: 1, duration: 0.15)

        hideTimer = Timer.scheduledTimer(withTimeInterval: Self.displayDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        guard let panel, panel.isVisible else { return }
        generation += 1
        let current = generation
        // Taken off screen once the fade is over, unless shown again in the meantime.
        let remove = { [weak self] in
            guard let self, self.generation == current else { return }
            panel.orderOut(nil)
            self.content = nil
        }
        let duration = fade(panel, to: 0, duration: 0.25)
        if duration == 0 {
            remove()
        } else {
            Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in
                MainActor.assumeIsolated(remove)
            }
        }
    }

    /// Bottom center of the screen the pointer is on, like the system overlays.
    static func origin(for size: CGSize) -> CGPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return .zero }
        return CGPoint(x: (visible.midX - size.width / 2).rounded(), y: visible.minY + bottomInset)
    }

    /// Animates the panel's alpha, or sets it at once under Reduce Motion. Returns the
    /// duration actually used.
    @discardableResult
    private func fade(_ panel: NSPanel, to alpha: CGFloat, duration: TimeInterval) -> TimeInterval {
        if reduceMotion() {
            panel.alphaValue = alpha
            return 0
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            panel.animator().alphaValue = alpha
        }
        return duration
    }

    private func makePanel(with content: HUDContent) -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: HUDView.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        // Above every app window, like the system volume overlay.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        panel.animationBehavior = .none
        // The card draws its own rounded shape; the window itself is clear.
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        let hosting = NSHostingView(rootView: HUDView(content: content))
        hosting.sizingOptions = []
        hosting.frame = CGRect(origin: .zero, size: HUDView.size)
        panel.contentView = hosting
        self.hosting = hosting
        self.panel = panel
        return panel
    }
}
