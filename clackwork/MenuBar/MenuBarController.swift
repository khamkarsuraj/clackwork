import AppKit
import Combine
import SwiftUI

/// Owns the menu bar item and the popover it opens (FR-17).
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let router: WindowRouter
    /// Watches the status item's window while the popover is open; see `followStatusItem`.
    private var moveObserver: NSObjectProtocol?
    /// Close the popover when the user goes elsewhere; see `closeWhenUserLeaves`.
    private var outsideClickMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var subscriptions: Set<AnyCancellable> = []

    init(appState: AppState, router: WindowRouter) {
        self.router = router
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
        }

        // The icon follows the state whichever way it changes: popover, window or shortcut.
        // @Published emits before the property is written, so use the emitted values.
        appState.$isEnabled
            .combineLatest(appState.$isMuted)
            .map { MenuBarIcon.State(isEnabled: $0, isMuted: $1) }
            .removeDuplicates()
            .sink { [weak self] state in
                self?.statusItem.button?.image = MenuBarIcon.image(for: state)
            }
            .store(in: &subscriptions)

        popover.behavior = .transient
        popover.delegate = self
        let content = PopoverView { [weak self] section in
            self?.showMainWindow(section: section)
        }
        .environmentObject(appState)
        popover.contentViewController = NSHostingController(rootView: content)
    }

    @objc func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Makes the popover key so its controls respond to the first click.
            popover.contentViewController?.view.window?.makeKey()
            followStatusItem()
            closeWhenUserLeaves()
        }
    }

    /// Only one menu bar menu should be open at a time. `.transient` closes the popover on
    /// outside clicks only while Clackwork is the active app; a click on another app's menu
    /// bar item (AirPods, Wi-Fi…) goes to that app, so watch for it here. Watching clicks in
    /// other apps needs no permission; only their key events would.
    private func closeWhenUserLeaves() {
        if outsideClickMonitor == nil {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.popover.performClose(nil) }
            }
        }
        if resignObserver == nil {
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.popover.performClose(nil) }
            }
        }
    }

    /// The icon moves when another app adds or removes a menu bar item, but the popover
    /// stays where it opened. Re-anchoring it on every move keeps it under the icon.
    private func followStatusItem() {
        guard moveObserver == nil, let window = statusItem.button?.window else { return }
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.popover.isShown, let button = self.statusItem.button else { return }
                // Setting the anchor again makes an open popover move to it; show() would not.
                self.popover.positioningRect = button.bounds
            }
        }
    }

    /// Brings the main window forward, reopening it if it was closed.
    private func showMainWindow(section: SidebarSection?) {
        popover.performClose(nil)
        if let section { router.section = section }
        NSApp.activate(ignoringOtherApps: true)
        router.openMainWindow?()
    }
}

extension MenuBarController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        moveObserver = nil
        resignObserver = nil
        outsideClickMonitor = nil
    }
}
