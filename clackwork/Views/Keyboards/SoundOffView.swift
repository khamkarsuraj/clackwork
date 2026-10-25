import SwiftUI

/// Empty state shown in the canvas when the app is disabled (PRD design principle 3).
struct SoundOffView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var shortcuts: ShortcutStore

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "keyboard")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 64, height: 64)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)

            Text("Sound is off")
                .font(.headline)
            Text("Clackwork isn’t listening to key events right now.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Button("Turn on sound") {
                appState.isEnabled = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if let combo = shortcuts.combo(for: .toggleSound) {
                Text("or press \(combo.display)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("or press \(combo.spokenDescription)")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

#Preview {
    SoundOffView()
        .environmentObject(AppState(defaults: UserDefaults(suiteName: "preview")!, engine: nil))
        .environmentObject(ShortcutStore(defaults: UserDefaults(suiteName: "preview")!))
        .frame(width: 700, height: 548)
}
