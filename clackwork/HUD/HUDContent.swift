import Foundation

/// What the shortcut HUD shows after an action: the new state, readable at a glance.
struct HUDContent: Equatable {
    enum Icon: Equatable {
        case symbol(String)
        case profile(KeyboardProfile)
    }

    let icon: Icon
    let title: String
    /// Second line: a hint such as "⌃⌥M to unmute" or "Keyboard 2 of 4".
    let detail: String?
    /// Text at the right of the title, such as "60%".
    let value: String?
    /// 0...1 for the volume bar; nil for the other HUDs.
    let progress: Double?

    /// The state right after `action` ran. `combo` is that action's own shortcut, used for
    /// the hint, so a customized shortcut shows as the user set it.
    init(after action: ShortcutAction, isEnabled: Bool, isMuted: Bool,
         profile: KeyboardProfile, volume: Double, combo: KeyCombo?) {
        switch action {
        case .toggleSound:
            self.init(
                icon: .symbol("power"),
                title: isEnabled ? "Sound on" : "Sound off",
                detail: combo.map { "\($0.compactDisplay) to turn \(isEnabled ? "off" : "on")" }
            )
        case .toggleMute:
            self.init(
                icon: .symbol(isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"),
                title: isMuted ? "Muted" : "Unmuted",
                detail: combo.map { "\($0.compactDisplay) to \(isMuted ? "unmute" : "mute")" }
            )
        case .nextKeyboard, .previousKeyboard:
            let all = KeyboardProfile.all
            let position = (all.firstIndex(of: profile) ?? 0) + 1
            self.init(icon: .profile(profile), title: profile.name, detail: "Keyboard \(position) of \(all.count)")
        case .volumeUp, .volumeDown:
            self.init(volume: volume)
        }
    }

    init(volume: Double) {
        self.init(
            icon: .symbol(volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill"),
            title: "Volume",
            detail: nil,
            value: "\(Int((volume * 100).rounded()))%",
            progress: volume
        )
    }

    private init(icon: Icon, title: String, detail: String?, value: String? = nil, progress: Double? = nil) {
        self.icon = icon
        self.title = title
        self.detail = detail
        self.value = value
        self.progress = progress
    }

    /// What VoiceOver reads for the HUD.
    var accessibilityLabel: String {
        [title, value, detail].compactMap { $0 }.joined(separator: ", ")
    }
}
