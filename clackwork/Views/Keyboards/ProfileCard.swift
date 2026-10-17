import SwiftUI

/// Compact card for one profile in the grid at the top of the Keyboards canvas.
struct ProfileCard: View {
    let profile: KeyboardProfile
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                swatch
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.shortName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(profile.family)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color(nsColor: .controlBackgroundColor) : Color.primary.opacity(0.05))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: isSelected ? 2 : 0)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(profile.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var swatch: some View {
        let palette = profile.palette(for: colorScheme)
        return HStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index == 2 ? palette.accent : palette.cap)
                    .frame(width: 12, height: 12)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .background(palette.body, in: RoundedRectangle(cornerRadius: 6))
    }
}
