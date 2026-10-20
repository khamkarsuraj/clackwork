import AppKit
import Carbon.HIToolbox

/// A key plus modifiers, as recorded in Settings and (later) registered system-wide.
struct KeyCombo: Codable, Hashable {
    var keyCode: UInt16
    var modifiers: UInt   // NSEvent.ModifierFlags raw value, device-independent bits only

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(.deviceIndependentFlagsMask).rawValue
    }

    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    /// "⌃ ⌥ O" style text, in Apple's modifier order.
    var display: String { parts.joined(separator: " ") }

    /// "⌃⌥O" style text, for running prose such as the HUD's "⌃⌥O to turn on".
    var compactDisplay: String { parts.joined() }

    private var parts: [String] {
        var parts: [String] = []
        let flags = modifierFlags
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        parts.append(KeyCombo.keyName(for: keyCode))
        return parts
    }

    /// Global shortcuts must include at least one modifier so plain typing never triggers them.
    var hasModifier: Bool {
        !modifierFlags.intersection([.control, .option, .shift, .command]).isEmpty
    }

    static func keyName(for keyCode: UInt16) -> String {
        if let name = specialKeys[Int(keyCode)] { return name }
        if let letter = ansiKeys[Int(keyCode)] { return letter }
        return "Key \(keyCode)"
    }

    private static let specialKeys: [Int: String] = [
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    private static let ansiKeys: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
        kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
        kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
        kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
        kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".",
        kVK_ANSI_Slash: "/", kVK_ANSI_Backslash: "\\", kVK_ANSI_Grave: "`",
    ]
}

/// The actions a global shortcut can trigger (PRD "Global shortcuts" table).
enum ShortcutAction: String, CaseIterable, Identifiable, Codable {
    case toggleSound
    case toggleMute
    case nextKeyboard
    case previousKeyboard
    case volumeUp
    case volumeDown
    /// Brings Clackwork forward with the cheat sheet of these shortcuts (issue #31).
    case showShortcuts

    var id: String { rawValue }

    var label: String {
        switch self {
        case .toggleSound: "Turn sound on or off"
        case .toggleMute: "Mute or unmute"
        case .nextKeyboard: "Next keyboard"
        case .previousKeyboard: "Previous keyboard"
        case .volumeUp: "Volume up"
        case .volumeDown: "Volume down"
        case .showShortcuts: "Show keyboard shortcuts"
        }
    }

    /// Defaults avoid common app shortcuts such as ⌘⇧S.
    var defaultCombo: KeyCombo {
        switch self {
        case .toggleSound: KeyCombo(keyCode: UInt16(kVK_ANSI_O), modifiers: [.control, .option])
        case .toggleMute: KeyCombo(keyCode: UInt16(kVK_ANSI_M), modifiers: [.control, .option])
        case .nextKeyboard: KeyCombo(keyCode: UInt16(kVK_RightArrow), modifiers: [.control, .option])
        case .previousKeyboard: KeyCombo(keyCode: UInt16(kVK_LeftArrow), modifiers: [.control, .option])
        case .volumeUp: KeyCombo(keyCode: UInt16(kVK_UpArrow), modifiers: [.control, .option])
        case .volumeDown: KeyCombo(keyCode: UInt16(kVK_DownArrow), modifiers: [.control, .option])
        case .showShortcuts: KeyCombo(keyCode: UInt16(kVK_ANSI_S), modifiers: [.control, .option])
        }
    }

    /// Earlier defaults. A stored copy of one of these means "the default at the time",
    /// not a choice, so the store reads it as the current default.
    var retiredDefaults: [KeyCombo] {
        switch self {
        case .toggleSound: [KeyCombo(keyCode: UInt16(kVK_ANSI_K), modifiers: [.control, .option])]
        default: []
        }
    }
}
