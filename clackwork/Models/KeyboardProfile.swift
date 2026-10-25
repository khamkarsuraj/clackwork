import SwiftUI

/// One of the keyboard sound profiles: Cobalt Clack, Walnut Bump, Onyx Thock and Ember Tap.
nonisolated struct KeyboardProfile: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let family: String
    let description: String
    let light: Palette
    let dark: Palette

    /// Colors used by the keyboard illustration and the profile card swatch.
    struct Palette: Hashable {
        let body: Color
        let cap: Color
        let modifier: Color
        let accent: Color
    }

    func palette(for scheme: ColorScheme) -> Palette {
        scheme == .dark ? dark : light
    }

    static let all: [KeyboardProfile] = [
        KeyboardProfile(
            id: "mx-blue",
            name: "Cobalt Clack",
            family: "Clicky",
            description: "Sharp, high-pitched click on every press. The loudest, most “typewriter” profile.",
            light: Palette(body: Color(hex: 0x2F3540), cap: Color(hex: 0xF2F2F2), modifier: Color(hex: 0xC9CED6), accent: Color(hex: 0x3A6FD8)),
            dark: Palette(body: Color(hex: 0x2F3540), cap: Color(hex: 0xD9DCE1), modifier: Color(hex: 0x8B929C), accent: Color(hex: 0x4F82E6))
        ),
        KeyboardProfile(
            id: "mx-brown",
            name: "Walnut Bump",
            family: "Tactile",
            description: "Soft bump, muted and office-friendly. A good default for long sessions.",
            light: Palette(body: Color(hex: 0x3B3B3D), cap: Color(hex: 0xECE7DD), modifier: Color(hex: 0xC9C1B2), accent: Color(hex: 0x8A5A3C)),
            dark: Palette(body: Color(hex: 0x3B3B3D), cap: Color(hex: 0xD6D0C5), modifier: Color(hex: 0x9A9284), accent: Color(hex: 0xA9765A))
        ),
        KeyboardProfile(
            id: "mx-black",
            name: "Onyx Thock",
            family: "Linear",
            description: "Heavy, smooth press with a deep, solid sound and no bump or click.",
            light: Palette(body: Color(hex: 0x1C1C1E), cap: Color(hex: 0x4A4A4E), modifier: Color(hex: 0x2E2E31), accent: Color(hex: 0x8E8E93)),
            dark: Palette(body: Color(hex: 0x111113), cap: Color(hex: 0x5A5A5F), modifier: Color(hex: 0x3E3E42), accent: Color(hex: 0x9A9AA0))
        ),
        KeyboardProfile(
            id: "mx-red",
            name: "Ember Tap",
            family: "Linear",
            description: "Light, smooth press with a soft, quiet sound. Fast and easy on the fingers.",
            light: Palette(body: Color(hex: 0xE5E5EA), cap: Color(hex: 0xFFFFFF), modifier: Color(hex: 0xD1D1D6), accent: Color(hex: 0xD9363E)),
            dark: Palette(body: Color(hex: 0x3A3A3D), cap: Color(hex: 0xD8D8DC), modifier: Color(hex: 0x9A9AA0), accent: Color(hex: 0xE5484D))
        ),
    ]

    /// The profile selected on first launch (PRD: Walnut Bump, the tactile profile, is the default).
    static let defaultProfile = all[1]
}

nonisolated extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
