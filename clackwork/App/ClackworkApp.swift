import Combine
import SwiftUI

@main
struct ClackworkApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @StateObject private var container = AppContainer()

    var body: some Scene {
        Window("Clackwork", id: "main") {
            MainWindowView()
                .environmentObject(container.appState)
                .environmentObject(container.shortcuts)
                .environmentObject(container.router)
                .frame(minWidth: 720, minHeight: 480)
        }
        .defaultSize(width: 900, height: 600)
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Clackwork lives in the menu bar, so closing the main window must not quit it.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        DebugSnapshot.runIfRequested()
        #endif
    }
}
