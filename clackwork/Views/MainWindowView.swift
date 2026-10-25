import SwiftUI

/// Sidebar sections of the main window.
enum SidebarSection: String, CaseIterable, Identifiable {
    case keyboards = "Keyboards"
    case shortcuts = "Shortcuts"
    case exclusions = "Exclusions"
    case settings = "Settings"

    /// The enum is its own ID so List selection matches the rows.
    var id: SidebarSection { self }

    var symbol: String {
        switch self {
        case .keyboards: "keyboard"
        case .shortcuts: "command"
        case .exclusions: "xmark.app"
        case .settings: "gearshape"
        }
    }
}

/// The three-pane main window: toolbar, sidebar, and the selected section's canvas.
/// On first launch it shows onboarding instead, until that is finished or skipped.
struct MainWindowView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: WindowRouter
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if appState.hasCompletedOnboarding {
                splitView
            } else {
                OnboardingView(appState: appState)
            }
        }
        .sheet(isPresented: $router.isShowingShortcutSheet) {
            ShortcutCheatSheet()
        }
        .onAppear {
            router.openMainWindow = { [openWindow] in openWindow(id: "main") }
        }
        // A sheet dies with its window; the flag must not outlive it, or reopening the
        // window would show the sheet unasked.
        .onDisappear { router.isShowingShortcutSheet = false }
    }

    private var splitView: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $router.section) { item in
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
                switch router.section ?? .keyboards {
                case .keyboards: KeyboardsView()
                case .shortcuts: ShortcutsView()
                case .exclusions: ExclusionsView()
                case .settings: SettingsView()
                }
            }
            .navigationTitle((router.section ?? .keyboards).rawValue)
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

    /// Width of the widest status label, so the switch stays put when the status changes.
    private static let labelWidth: CGFloat = {
        let font = NSFont.preferredFont(forTextStyle: .caption1)
        // The paused label carries an app name; a typical one sets the width, longer ones clip.
        return ["Sound on", "Sound off", "Muted", "Muted · microphone in use", "Paused · Google Chrome in front"]
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width.rounded(.up) }
            .max() ?? 0
    }()

    /// A manual mute wins over auto-mute in the wording, as in the popover: the user asked for it.
    private var status: String {
        guard appState.isEnabled else { return "Sound off" }
        if appState.isMuted { return "Muted" }
        if appState.isAutoMuted { return "Muted · microphone in use" }
        if let app = appState.excludedAppInFront { return "Paused · \(app.name) in front" }
        return "Sound on"
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
                // While the sidebar animates the toolbar can briefly offer less room. The label
                // is clipped from the leading edge then, so the item never overflows into the
                // toolbar's chevron menu and the switch never moves.
                .frame(minWidth: 0, idealWidth: Self.labelWidth, maxWidth: Self.labelWidth, alignment: .trailing)
                .clipped()
            Toggle("Sound", isOn: $appState.isEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .accessibilityLabel("Sound")
                .fixedSize()
        }
        .padding(.trailing, 4)
    }
}

#Preview {
    MainWindowView()
        .environmentObject(AppState(defaults: UserDefaults(suiteName: "preview")!, engine: nil))
        .environmentObject(ShortcutStore(defaults: UserDefaults(suiteName: "preview")!))
        .environmentObject(WindowRouter())
        .frame(width: 900, height: 600)
}
