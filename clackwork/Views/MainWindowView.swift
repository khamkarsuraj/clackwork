import SwiftUI

/// Sidebar sections of the main window.
enum SidebarSection: String, CaseIterable, Identifiable {
    case keyboards = "Keyboards"
    case shortcuts = "Shortcuts"
    case settings = "Settings"

    /// The enum is its own ID so List selection matches the rows.
    var id: SidebarSection { self }

    var symbol: String {
        switch self {
        case .keyboards: "keyboard"
        case .shortcuts: "command"
        case .settings: "gearshape"
        }
    }
}

/// The three-pane main window: toolbar, sidebar, and the selected section's canvas.
struct MainWindowView: View {
    @EnvironmentObject private var appState: AppState
    @State private var section: SidebarSection? = {
        #if DEBUG
        DebugSnapshot.initialSection ?? .keyboards
        #else
        .keyboards
        #endif
    }()

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $section) { item in
                Label(item.rawValue, systemImage: item.symbol)
                    // No type-to-select: typing K or S while testing sounds must not switch sections.
                    .typeSelectEquivalent("")
            }
            .listStyle(.sidebar)
            // Sections switch by mouse only; arrow keys are swallowed here.
            .onMoveCommand { _ in }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            Group {
                switch section ?? .keyboards {
                case .keyboards: KeyboardsView()
                case .shortcuts: ShortcutsView()
                case .settings: SettingsView()
                }
            }
            .navigationTitle((section ?? .keyboards).rawValue)
            .toolbar {
                if #available(macOS 26, *) {
                    ToolbarItem(placement: .primaryAction) {
                        MasterToggle()
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .primaryAction) {
                        MasterToggle()
                    }
                }
            }
        }
    }
}

/// The on/off switch that lives at the right of the toolbar (FR-12).
private struct MasterToggle: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 6) {
            Text(appState.isEnabled ? (appState.isMuted ? "Muted" : "Sound on") : "Sound off")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Sound", isOn: $appState.isEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .accessibilityLabel("Sound")
        }
        .padding(.trailing, 4)
    }
}

#Preview {
    MainWindowView()
        .environmentObject(AppState(defaults: UserDefaults(suiteName: "preview")!, engine: nil))
        .environmentObject(ShortcutStore(defaults: UserDefaults(suiteName: "preview")!))
        .frame(width: 900, height: 600)
}
