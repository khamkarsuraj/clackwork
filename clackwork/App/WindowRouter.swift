import Combine

/// Which sidebar section the main window shows, shared so the menu bar popover can open
/// the window on a given section (e.g. "Settings").
final class WindowRouter: ObservableObject {
    @Published var section: SidebarSection? = {
        #if DEBUG
        DebugSnapshot.initialSection ?? .keyboards
        #else
        .keyboards
        #endif
    }()

    /// Brings the main window forward, reopening it if it was closed. Set by the main window
    /// on first appearance, since only SwiftUI views get the `openWindow` action.
    var openMainWindow: (() -> Void)?
}
