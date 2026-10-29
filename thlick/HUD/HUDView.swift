import SwiftUI

/// The shortcut HUD card: an icon and the new state, in the style of the system volume
/// overlay. System materials and colors keep it right in light and dark mode.
struct HUDView: View {
    let content: HUDContent

    static let size = CGSize(width: 300, height: 64)
    private static let cornerRadius: CGFloat = 18

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 14) {
            icon
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: content.progress == nil ? 2 : 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(content.title)
                        .font(.system(size: content.progress == nil ? 15 : 13, weight: .semibold))
                        .lineLimit(1)
                    if let value = content.value {
                        Spacer(minLength: 8)
                        Text(value)
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                    }
                }
                if let detail = content.detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let progress = content.progress {
                    bar(progress)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilityLabel)
    }

    @ViewBuilder
    private var icon: some View {
        switch content.icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 22, weight: .regular))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .profile(let profile):
            // A key in the profile's colors, matching the swatch on its card.
            let palette = profile.palette(for: colorScheme)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(palette.body)
                .overlay {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(palette.cap)
                        .frame(width: 14, height: 14)
                        .overlay(alignment: .bottom) {
                            Capsule()
                                .fill(palette.accent)
                                .frame(width: 8, height: 2)
                                .padding(.bottom, 3)
                        }
                }
        }
    }

    private func bar(_ progress: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.12))
                Capsule().fill(.primary)
                    .frame(width: proxy.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: 6)
    }
}

#Preview("States") {
    let brown = KeyboardProfile.defaultProfile
    let mute = ShortcutAction.toggleMute.defaultCombo
    let sound = ShortcutAction.toggleSound.defaultCombo
    VStack(spacing: 16) {
        HUDView(content: HUDContent(after: .toggleMute, isEnabled: true, isMuted: true, profile: brown, volume: 0.6, combo: mute))
        HUDView(content: HUDContent(after: .nextKeyboard, isEnabled: true, isMuted: false, profile: brown, volume: 0.6, combo: nil))
        HUDView(content: HUDContent(volume: 0.6))
        HUDView(content: HUDContent(after: .toggleSound, isEnabled: false, isMuted: false, profile: brown, volume: 0.6, combo: sound))
    }
    .padding(40)
    .background(Color(nsColor: .windowBackgroundColor))
}
