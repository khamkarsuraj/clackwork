import AppKit
import SwiftUI

/// The Shortcuts section: one recordable row per global action.
struct ShortcutsView: View {
    @EnvironmentObject private var shortcuts: ShortcutStore

    var body: some View {
        Form {
            Section {
                ForEach(ShortcutAction.allCases) { action in
                    LabeledContent(action.label) {
                        ShortcutRecorderButton(
                            combo: shortcuts.combo(for: action),
                            isRecording: shortcuts.recording == action,
                            start: { shortcuts.recording = action },
                            finish: { combo in
                                if let combo { shortcuts.set(combo, for: action) }
                                shortcuts.recording = nil
                            }
                        )
                    }
                }
            } header: {
                Text("Click a shortcut, then press the new key combination. These work in every app.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                    .padding(.bottom, 4)
            } footer: {
                HStack {
                    Text("Defaults avoid common app shortcuts like ⌘⇧S.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Restore Defaults") {
                        shortcuts.recording = nil
                        shortcuts.restoreDefaults()
                    }
                }
                .padding(.top, 4)
            }
        }
        .formStyle(.grouped)
    }
}

/// Shows a shortcut as key caps; click to record a new one. Escape cancels.
struct ShortcutRecorderButton: View {
    let combo: KeyCombo?
    let isRecording: Bool
    let start: () -> Void
    let finish: (KeyCombo?) -> Void

    @State private var monitor: Any?

    var body: some View {
        Button(action: start) {
            KeyCap(
                text: isRecording ? "Press new shortcut…" : (combo?.display ?? "Not set"),
                style: isRecording ? .recording : (combo == nil ? .unset : .set),
                width: 150
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Change shortcut")
        .accessibilityValue(combo?.display ?? "Not set")
        .onChange(of: isRecording) { recording in
            recording ? installMonitor() : removeMonitor()
        }
        .onDisappear(perform: removeMonitor)
    }

    private func installMonitor() {
        removeMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape
                finish(nil)
                return nil
            }
            let combo = KeyCombo(keyCode: event.keyCode, modifiers: event.modifierFlags)
            guard combo.hasModifier else {
                NSSound.beep()
                return nil
            }
            finish(combo)
            return nil
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

#Preview {
    ShortcutsView()
        .environmentObject(ShortcutStore(defaults: UserDefaults(suiteName: "preview")!))
        .frame(width: 700, height: 548)
}
