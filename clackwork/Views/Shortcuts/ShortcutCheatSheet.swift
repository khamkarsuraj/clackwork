import SwiftUI

/// The shortcut cheat sheet: every shortcut with its current key combination (PRD design
/// principle 5). The "Show keyboard shortcuts" global shortcut (⌃⌥S by default) opens it
/// from any app and closes it again; so do Escape and Done.
struct ShortcutCheatSheet: View {
    @EnvironmentObject private var shortcuts: ShortcutStore
    @EnvironmentObject private var router: WindowRouter

    /// One line of the sheet. `keys` is nil for an unassigned shortcut.
    struct Row: Identifiable, Equatable {
        let id: String
        let label: String
        let keys: String?
    }

    /// The shortcuts as the user has them set right now.
    static func rows(from store: ShortcutStore) -> [Row] {
        ShortcutAction.allCases.map { action in
            Row(id: action.id, label: action.label, keys: store.combo(for: action)?.display)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Keyboard Shortcuts")
                    .font(.title2.weight(.semibold))
                Text("These work in every app, even while Clackwork is in the background.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 16)

            VStack(spacing: 0) {
                let rows = Self.rows(from: shortcuts)
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    HStack {
                        Text(row.label)
                        Spacer()
                        KeyCap(text: row.keys ?? "Not set", style: row.keys == nil ? .unset : .set)
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 12)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(row.label), \(row.keys ?? "not set")")
                    if index < rows.count - 1 {
                        Divider().padding(.leading, 12)
                    }
                }
            }
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack {
                Button("Customize…") {
                    router.isShowingShortcutSheet = false
                    router.section = .shortcuts
                }
                Spacer()
                Button("Done") { router.isShowingShortcutSheet = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 20)
        }
        .padding(24)
        .frame(width: 440)
        .onExitCommand { router.isShowingShortcutSheet = false }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Keyboard shortcuts")
    }
}

#Preview {
    ShortcutCheatSheet()
        .environmentObject(ShortcutStore(defaults: UserDefaults(suiteName: "preview")!))
        .environmentObject(WindowRouter())
}
