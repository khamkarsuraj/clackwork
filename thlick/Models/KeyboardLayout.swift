import Carbon.HIToolbox
import Foundation

/// The compact 60% layout drawn by `KeyboardIllustration`, and where each key code sits on it.
///
/// Used only to animate the on-screen keyboard. Positions are never stored or logged.
nonisolated enum KeyboardLayout {
    /// One key on the drawn board.
    struct Location: Hashable {
        let row: Int
        let column: Int

        static let space = Location(row: 4, column: 3)

        /// A random letter key in the three alpha rows, for sounds with no known key.
        static func random() -> Location {
            Location(row: Int.random(in: 1...3), column: Int.random(in: 1...9))
        }
    }

    /// Key widths in units per row, matching the design canvas.
    static let rows: [[Double]] = [
        [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2],
        [1.5, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1.5],
        [1.75, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2.25],
        [2.25, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2.75],
        [1.25, 1.25, 1.25, 6.25, 1.25, 1.25, 1.25, 1.25],
    ]

    /// Where a key code is drawn, or nil for keys the compact board doesn't have (arrows, F-keys…).
    static func location(for keyCode: Int) -> Location? {
        locations[keyCode]
    }

    private static let locations: [Int: Location] = {
        var map: [Int: Location] = [:]
        func row(_ r: Int, _ codes: [Int]) {
            for (c, code) in codes.enumerated() { map[code] = Location(row: r, column: c) }
        }
        row(0, [kVK_ANSI_Grave, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6,
                kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9, kVK_ANSI_0, kVK_ANSI_Minus, kVK_ANSI_Equal, kVK_Delete])
        row(1, [kVK_Tab, kVK_ANSI_Q, kVK_ANSI_W, kVK_ANSI_E, kVK_ANSI_R, kVK_ANSI_T, kVK_ANSI_Y,
                kVK_ANSI_U, kVK_ANSI_I, kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_LeftBracket, kVK_ANSI_RightBracket,
                kVK_ANSI_Backslash])
        row(2, [kVK_CapsLock, kVK_ANSI_A, kVK_ANSI_S, kVK_ANSI_D, kVK_ANSI_F, kVK_ANSI_G, kVK_ANSI_H,
                kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_Semicolon, kVK_ANSI_Quote, kVK_Return])
        row(3, [kVK_Shift, kVK_ANSI_Z, kVK_ANSI_X, kVK_ANSI_C, kVK_ANSI_V, kVK_ANSI_B, kVK_ANSI_N,
                kVK_ANSI_M, kVK_ANSI_Comma, kVK_ANSI_Period, kVK_ANSI_Slash, kVK_RightShift])
        row(4, [kVK_Control, kVK_Option, kVK_Command, kVK_Space, kVK_RightCommand, kVK_RightOption,
                kVK_Function, kVK_RightControl])
        // Keys with an obvious stand-in on a compact board.
        map[kVK_Escape] = Location(row: 0, column: 0)
        map[kVK_ANSI_KeypadEnter] = Location(row: 2, column: 12)
        map[kVK_ForwardDelete] = Location(row: 0, column: 13)
        return map
    }()
}

/// What the listener reports: the kind of key, whether it went down or up, where it is drawn,
/// and when it happened (for latency measurement only).
nonisolated struct KeyEvent: Hashable {
    let type: KeyType
    let isDown: Bool
    let location: KeyboardLayout.Location?
    /// Hardware event time, nanoseconds on the uptime clock.
    var eventNanos: UInt64 = 0
    /// When the event tap received it, nanoseconds on the uptime clock.
    var tapNanos: UInt64 = 0
}
