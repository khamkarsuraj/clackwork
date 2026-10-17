import Combine
import Foundation

/// Owns the app's long-lived objects so they are created once and in the right order.
final class AppContainer: ObservableObject {
    let appState: AppState
    let shortcuts: ShortcutStore
    let hotKeys: HotKeyCenter

    init() {
        appState = AppState()
        shortcuts = ShortcutStore()
        hotKeys = HotKeyCenter(appState: appState, shortcuts: shortcuts)
    }
}
