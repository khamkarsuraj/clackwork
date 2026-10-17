import Foundation

/// The only thing the app ever derives from a keystroke: which kind of key it was.
/// Characters are never inspected or stored (PRD privacy requirement).
enum KeyType: String, CaseIterable, Hashable {
    case standard
    case space
    case returnKey
    case backspace
    case modifier
}
