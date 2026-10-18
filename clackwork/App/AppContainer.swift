import Combine
import Foundation

/// Owns the app's long-lived objects so they are created once and in the right order.
final class AppContainer: ObservableObject {
    let appState: AppState
    let shortcuts: ShortcutStore
    let hotKeys: HotKeyCenter
    let router: WindowRouter
    let menuBar: MenuBarController

    init() {
        appState = AppState()
        shortcuts = ShortcutStore()
        hotKeys = HotKeyCenter(appState: appState, shortcuts: shortcuts)
        router = WindowRouter()
        menuBar = MenuBarController(appState: appState, router: router)
    }
}
