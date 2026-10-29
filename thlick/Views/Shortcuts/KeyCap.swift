import SwiftUI

/// A key combination drawn as a key cap. The recorder in Settings and the cheat sheet
/// share it, so the two always look the same.
struct KeyCap: View {
    enum Style {
        /// A combination is set.
        case set
        /// Nothing assigned: "Not set".
        case unset
        /// The recorder is waiting for a key press.
        case recording
    }

    let text: String
    let style: Style
    /// Fixed width for the recorder, so rows line up; the cheat sheet fits to the text.
    var width: CGFloat? = nil

    var body: some View {
        Text(text)
            .font(.caption.weight(style == .recording ? .medium : .regular))
            .tracking(style == .set ? 1 : 0)
            .monospacedDigit()
            .padding(.horizontal, 10)
            .frame(width: width, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(style == .recording ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(style == .recording ? Color.accentColor : Color.primary.opacity(0.16),
                                  lineWidth: style == .recording ? 2 : 0.5)
            )
            .foregroundStyle(foreground)
    }

    private var foreground: Color {
        switch style {
        case .set: .primary
        case .unset: .secondary
        case .recording: .accentColor
        }
    }
}
