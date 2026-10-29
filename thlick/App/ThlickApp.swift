import Combine
import SwiftUI

@main
struct ThlickApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @StateObject private var container = AppContainer()

    var body: some Scene {
        Window("Thlick", id: "main") {
            MainWindowView()
                .environmentObject(container.appState)
                .environmentObject(container.shortcuts)
                .environmentObject(container.exclusions)
                .environmentObject(container.router)
                .frame(minWidth: 720, minHeight: 480)
        }
        .defaultSize(width: 900, height: 600)
        .windowResizability(.contentMinSize)
        .commands {
            // Keyboard access to the sidebar (⌘1 to ⌘4). Arrow keys stay off in the sidebar
            // itself, so pressing them to hear sounds never switches sections.
            CommandGroup(before: .sidebar) {
                ForEach(Array(SidebarSection.allCases.enumerated()), id: \.element) { index, section in
                    Button(section.rawValue) { container.router.showMainWindow(section: section) }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
                Divider()
            }
            CommandGroup(after: .help) {
                // No key equivalent here: the global "Show keyboard shortcuts" hot key
                // (⌃⌥S by default) already covers it, inside the app and out.
                Button("Keyboard Shortcuts") { container.router.toggleShortcutSheet() }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Thlick lives in the menu bar, so closing the main window must not quit it.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        DebugSnapshot.runIfRequested()
        #endif
    }
}
