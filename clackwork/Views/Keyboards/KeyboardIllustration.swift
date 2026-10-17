import SwiftUI

/// A stylized 60% keyboard drawn from the selected profile's palette.
/// Keys in `pressedKeys` are drawn sunk, so held modifiers and chords show correctly.
struct KeyboardIllustration: View {
    typealias KeyID = KeyboardLayout.Location

    let palette: KeyboardProfile.Palette
    let pressedKeys: Set<KeyID>

    private static let layout = KeyboardLayout.rows

    private let gap: CGFloat = 3
    private let keyHeight: CGFloat = 19

    var body: some View {
        VStack(spacing: gap) {
            ForEach(Array(Self.layout.enumerated()), id: \.offset) { rowIndex, row in
                GeometryReader { geometry in
                    let totalUnits = row.reduce(0, +)
                    let unitWidth = (geometry.size.width - gap * CGFloat(row.count - 1)) / totalUnits
                    HStack(spacing: gap) {
                        ForEach(Array(row.enumerated()), id: \.offset) { columnIndex, units in
                            let id = KeyID(row: rowIndex, column: columnIndex)
                            key(id: id, color: color(for: id, units: units, rowCount: row.count))
                                .frame(width: unitWidth * units)
                        }
                    }
                }
                .frame(height: keyHeight)
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.body)
                .shadow(color: .black.opacity(0.2), radius: 11, y: 8)
        }
        .accessibilityHidden(true)
    }

    private func key(id: KeyID, color: Color) -> some View {
        let isDown = pressedKeys.contains(id)
        return RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(.black.opacity(0.2))
                    .frame(height: isDown ? 1 : 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .offset(y: isDown ? 2 : 0)
            .animation(.easeOut(duration: 0.07), value: isDown)
    }

    private func color(for id: KeyID, units: Double, rowCount: Int) -> Color {
        let isAccent = (id.row == 0 && id.column == 0) || (id.row == 2 && id.column == rowCount - 1)
        if isAccent { return palette.accent }
        let isModifier = units != 1 && id != .space
        return isModifier ? palette.modifier : palette.cap
    }
}

#Preview {
    KeyboardIllustration(palette: KeyboardProfile.defaultProfile.light, pressedKeys: [.space])
        .frame(width: 340)
        .padding(40)
}
