import AppKit
import Carbon.HIToolbox
import Combine

/// Registers the user's shortcuts as system-wide hot keys and routes them to actions.
///
/// Uses Carbon `RegisterEventHotKey`, which works from any app, inside the sandbox,
/// and needs no Accessibility or Input Monitoring permission.
final class HotKeyCenter {
    private let appState: AppState
    private var registered: [UInt32: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private var subscriptions: Set<AnyCancellable> = []

    private static let signature: OSType = 0x434C434B // "CLCK"
    private static let actions = ShortcutAction.allCases

    init(appState: AppState, shortcuts: ShortcutStore) {
        self.appState = appState
        installHandler()
        // @Published emits before the property is written, so always register from the
        // emitted values rather than re-reading the store.
        shortcuts.$combos
            .combineLatest(shortcuts.$recording)
            .sink { [weak self] combos, recording in
                // While a shortcut is being recorded, nothing may fire.
                self?.register(recording == nil ? combos : [:])
            }
            .store(in: &subscriptions)
    }

    deinit {
        for ref in registered.values { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }

    /// Runs the action for a hot key ID. Called from the Carbon handler on the main thread.
    func handle(id: UInt32) {
        guard Self.actions.indices.contains(Int(id)) else { return }
        perform(Self.actions[Int(id)])
    }

    func perform(_ action: ShortcutAction) {
        switch action {
        case .toggleSound: appState.isEnabled.toggle()
        case .toggleMute: appState.toggleMute()
        case .nextKeyboard: appState.selectKeyboard(offset: 1)
        case .previousKeyboard: appState.selectKeyboard(offset: -1)
        case .volumeUp: appState.adjustVolume(by: 0.05)
        case .volumeDown: appState.adjustVolume(by: -0.05)
        }
    }

    private func register(_ combos: [ShortcutAction: KeyCombo?]) {
        for ref in registered.values { UnregisterEventHotKey(ref) }
        registered.removeAll()

        for (index, action) in Self.actions.enumerated() {
            guard let combo = combos[action] ?? nil else { continue }
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(index))
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(combo.keyCode), Self.carbonModifiers(combo.modifierFlags),
                id, GetApplicationEventTarget(), 0, &ref
            )
            if status == noErr, let ref {
                registered[UInt32(index)] = ref
            } else {
                NSLog("HotKeyCenter: could not register \(combo.display) for \(action.rawValue) (status \(status))")
            }
        }
    }

    private func installHandler() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            guard status == noErr, hotKeyID.signature == HotKeyCenter.signature else {
                return OSStatus(eventNotHandledErr)
            }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { center.handle(id: hotKeyID.id) }
            return noErr
        }, 1, &type, userData, &handler)
    }

    private static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        return mods
    }
}
