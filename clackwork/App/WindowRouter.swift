import AppKit
import Combine

/// Which sidebar section the main window shows, shared so the menu bar popover can open
/// the window on a given section (e.g. "Settings"), and whether the shortcut cheat sheet is up.
final class WindowRouter: ObservableObject {
    @Published var section: SidebarSection? = {
        #if DEBUG
        DebugSnapshot.initialSection ?? .keyboards
        #else
        .keyboards
        #endif
    }()

    /// Whether the shortcut cheat sheet is up on the main window.
    @Published var isShowingShortcutSheet = false

    /// Brings the main window forward, reopening it if it was closed. Set by the main window
    /// on first appearance, since only SwiftUI views get the `openWindow` action.
    var openMainWindow: (() -> Void)?

    /// Whether Clackwork is the frontmost app. Replaced in tests.
    var isAppActive: () -> Bool = { NSApp?.isActive ?? false }

    /// Brings the main window forward, on `section` if given, reopening it if it was closed.
    func showMainWindow(section: SidebarSection? = nil) {
        if let section { self.section = section }
        NSApp?.activate(ignoringOtherApps: true)
        openMainWindow?()
    }

    /// The "Show keyboard shortcuts" hot key (⌃⌥S by default) and Help > Keyboard Shortcuts.
    /// Shows the sheet and brings Clackwork forward; hides it only when it is up and
    /// Clackwork is in front, so a press from another app always ends with the sheet visible.
    func toggleShortcutSheet() {
        if isShowingShortcutSheet && isAppActive() {
            isShowingShortcutSheet = false
        } else {
            isShowingShortcutSheet = true
            showMainWindow()
        }
    }
}
