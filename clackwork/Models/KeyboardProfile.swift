import SwiftUI

/// One of the five keyboard sound profiles shipped in v1.0.
nonisolated struct KeyboardProfile: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let shortName: String
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
            name: "Cherry MX Blue style",
            shortName: "MX Blue style",
            family: "Clicky",
            description: "Sharp, high-pitched click on every press. The loudest, most “typewriter” profile.",
            light: Palette(body: Color(hex: 0x2F3540), cap: Color(hex: 0xF2F2F2), modifier: Color(hex: 0xC9CED6), accent: Color(hex: 0x3A6FD8)),
            dark: Palette(body: Color(hex: 0x2F3540), cap: Color(hex: 0xD9DCE1), modifier: Color(hex: 0x8B929C), accent: Color(hex: 0x4F82E6))
        ),
        KeyboardProfile(
            id: "mx-brown",
            name: "Cherry MX Brown style",
            shortName: "MX Brown style",
            family: "Tactile",
            description: "Soft bump, muted and office-friendly. A good default for long sessions.",
            light: Palette(body: Color(hex: 0x3B3B3D), cap: Color(hex: 0xECE7DD), modifier: Color(hex: 0xC9C1B2), accent: Color(hex: 0x8A5A3C)),
            dark: Palette(body: Color(hex: 0x3B3B3D), cap: Color(hex: 0xD6D0C5), modifier: Color(hex: 0x9A9284), accent: Color(hex: 0xA9765A))
        ),
        KeyboardProfile(
            id: "lubed-linear",
            name: "Lubed linear (Gateron Yellow style)",
            shortName: "Lubed linear",
            family: "Linear",
            description: "Deep, smooth “thock” with no bump or click.",
            light: Palette(body: Color(hex: 0xE8DCBC), cap: Color(hex: 0xFBF7EC), modifier: Color(hex: 0xE6D9B5), accent: Color(hex: 0xD9A520)),
            dark: Palette(body: Color(hex: 0x5A5240), cap: Color(hex: 0xE3DCC8), modifier: Color(hex: 0xA69B7E), accent: Color(hex: 0xE2B23A))
        ),
        KeyboardProfile(
            id: "model-m",
            name: "IBM Model M",
            shortName: "IBM Model M",
            family: "Buckling spring",
            description: "Loud, vintage, metallic ping from a buckling spring.",
            light: Palette(body: Color(hex: 0xD3CCBD), cap: Color(hex: 0xE4DED0), modifier: Color(hex: 0x9C9C9C), accent: Color(hex: 0x9C9C9C)),
            dark: Palette(body: Color(hex: 0x57534A), cap: Color(hex: 0xCFC8B8), modifier: Color(hex: 0x8C8C8C), accent: Color(hex: 0x9C9C9C))
        ),
        KeyboardProfile(
            id: "topre",
            name: "Topre (HHKB style)",
            shortName: "Topre (HHKB style)",
            family: "Electro-capacitive",
            description: "Rounded, cushioned “thock” with a light, even feel.",
            light: Palette(body: Color(hex: 0x4A4D52), cap: Color(hex: 0xE3E3E0), modifier: Color(hex: 0x5F6368), accent: Color(hex: 0x5F6368)),
            dark: Palette(body: Color(hex: 0x4A4D52), cap: Color(hex: 0xD4D4D1), modifier: Color(hex: 0x6B7076), accent: Color(hex: 0x6B7076))
        ),
    ]

    /// The profile selected on first launch (PRD: MX Brown style is the default).
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
