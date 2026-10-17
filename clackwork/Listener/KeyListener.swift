import Carbon.HIToolbox
@preconcurrency import CoreFoundation
import CoreGraphics
import Foundation

/// A listen-only event tap that reports which *kind* of key was pressed, system-wide (FR-1).
///
/// Privacy: what leaves this class is a `KeyEvent`: the key's category, down or up, and its
/// position on the drawn keyboard for the animation. Characters are never read or stored.
/// Secure input fields (passwords) are skipped (FR-6), as are auto-repeat events from held
/// keys (FR-5). Needs Input Monitoring permission.
nonisolated final class KeyListener: @unchecked Sendable {
    /// Called on the listener thread for every key down, before anything else.
    /// Keep it fast: this is where the sound is played.
    private let onKeyDown: @Sendable (KeyEvent) -> Void
    /// Called on the main thread for every key down and key up, for the UI.
    private let onEvent: @MainActor (KeyEvent) -> Void

    private let lock = NSLock()
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var thread: Thread?

    init(onKeyDown: @escaping @Sendable (KeyEvent) -> Void,
         onEvent: @escaping @MainActor (KeyEvent) -> Void) {
        self.onKeyDown = onKeyDown
        self.onEvent = onEvent
    }

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return tap != nil
    }

    static var hasAccess: Bool { CGPreflightListenEventAccess() }

    /// Prompts for Input Monitoring (also adds the app to the list in System Settings).
    @discardableResult
    static func requestAccess() -> Bool { CGRequestListenEventAccess() }

    /// Starts listening. Returns false when the tap could not be created, usually for lack of permission.
    @discardableResult
    func start() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if tap != nil { return true }

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                if let userInfo {
                    Unmanaged<KeyListener>.fromOpaque(userInfo).takeUnretainedValue().handle(type: type, event: event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        ) else { return false }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let thread = Thread { [weak self] in
            guard let self else { return }
            let runLoop = CFRunLoopGetCurrent()
            lock.lock()
            // stop() may already have run; don't enable a tap that was invalidated.
            guard self.tap === tap else { lock.unlock(); return }
            self.runLoop = runLoop
            lock.unlock()
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "Clackwork key listener"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
        return true
    }

    func stop() {
        lock.lock(); defer { lock.unlock() }
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        if let runLoop { CFRunLoopStop(runLoop) }
        self.tap = nil
        self.runLoop = nil
        self.thread = nil
    }

    // MARK: Event handling (listener thread)

    private func handle(type: CGEventType, event: CGEvent) {
        let isDown: Bool
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS disables taps that look stuck; just turn it back on.
            lock.lock()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            lock.unlock()
            return
        case .keyDown:
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return }
            isDown = true
        case .keyUp:
            isDown = false
        case .flagsChanged:
            // Modifier keys only report flag changes; derive down/up from the flag state.
            isDown = Self.isModifierDown(event)
        default:
            return
        }
        guard !IsSecureEventInputEnabled() else { return }

        let tapNanos = LatencyProbe.now()
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let keyEvent = KeyEvent(
            type: Self.keyType(for: keyCode),
            isDown: isDown,
            location: KeyboardLayout.location(for: Int(keyCode)),
            eventNanos: LatencyProbe.eventNanos(fromTimestamp: event.timestamp, now: tapNanos),
            tapNanos: tapNanos
        )
        if isDown { onKeyDown(keyEvent) }
        DispatchQueue.main.async { [onEvent] in
            MainActor.assumeIsolated { onEvent(keyEvent) }
        }
    }

    /// Classifies a key code. Letters, digits and punctuation are all "standard"; nothing finer is kept.
    static func keyType(for keyCode: Int64) -> KeyType {
        switch Int(keyCode) {
        case kVK_Space:
            return .space
        case kVK_Return, kVK_ANSI_KeypadEnter:
            return .returnKey
        case kVK_Delete, kVK_ForwardDelete:
            return .backspace
        case kVK_Shift, kVK_RightShift, kVK_Control, kVK_RightControl,
             kVK_Option, kVK_RightOption, kVK_Command, kVK_RightCommand,
             kVK_CapsLock, kVK_Function:
            return .modifier
        default:
            return .standard
        }
    }

    private static func isModifierDown(_ event: CGEvent) -> Bool {
        let flags = event.flags
        switch Int(event.getIntegerValueField(.keyboardEventKeycode)) {
        case kVK_Shift, kVK_RightShift: return flags.contains(.maskShift)
        case kVK_Control, kVK_RightControl: return flags.contains(.maskControl)
        case kVK_Option, kVK_RightOption: return flags.contains(.maskAlternate)
        case kVK_Command, kVK_RightCommand: return flags.contains(.maskCommand)
        case kVK_CapsLock: return flags.contains(.maskAlphaShift)
        case kVK_Function: return flags.contains(.maskSecondaryFn)
        default: return false
        }
    }
}
