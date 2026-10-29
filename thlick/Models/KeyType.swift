import Foundation

/// The only thing the app ever derives from a keystroke: which kind of key it was.
/// Characters are never inspected or stored (PRD privacy requirement).
nonisolated enum KeyType: String, CaseIterable, Hashable, Sendable {
    case standard
    case space
    case returnKey
    case backspace
    case modifier
}
