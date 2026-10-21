import Combine
import Foundation

/// Owns the app's long-lived objects so they are created once and in the right order.
final class AppContainer: ObservableObject {
    let appState: AppState
    let shortcuts: ShortcutStore
    let exclusions: ExclusionStore
    let hud: HUDController
    let hotKeys: HotKeyCenter
    let router: WindowRouter
    let menuBar: MenuBarController

    init() {
        exclusions = ExclusionStore()
        appState = AppState(exclusions: exclusions)
        shortcuts = ShortcutStore()
        hud = HUDController()
        router = WindowRouter()
        hotKeys = HotKeyCenter(appState: appState, shortcuts: shortcuts, hud: hud, router: router)
        menuBar = MenuBarController(appState: appState, router: router)
    }
}
