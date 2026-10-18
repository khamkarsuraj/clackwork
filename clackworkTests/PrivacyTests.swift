import Testing
@testable import clackwork

/// PRD privacy requirement: the listener's output carries the kind of key, never characters.
struct PrivacyTests {
    @Test func keyEventCarriesNoCharacters() {
        let event = KeyEvent(type: .standard, isDown: true, location: nil)
        let fields = Mirror(reflecting: event).children.compactMap(\.label)
        // Adding a field here needs a privacy review: it must not identify which character was typed.
        #expect(fields == ["type", "isDown", "location", "eventNanos", "tapNanos"])
    }

    @Test func keyTypesAreCategoriesOnly() {
        #expect(KeyType.allCases.map(\.rawValue) == ["standard", "space", "returnKey", "backspace", "modifier"])
    }
}
