import SwiftUI

/// The Settings section: general options, sound options, and the permission status.
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("General") {
                SettingRow("Open at login", help: "Start Clackwork when you log in to your Mac.") {
                    Toggle("Open at login", isOn: $appState.launchAtLogin)
                }
                SettingRow("Show icon in Dock", help: "Off keeps Clackwork in the menu bar only.") {
                    Toggle("Show icon in Dock", isOn: $appState.showDockIcon)
                }
                SettingRow("Show HUD for shortcuts", help: "Briefly show what changed, like the volume overlay.") {
                    Toggle("Show HUD for shortcuts", isOn: $appState.showHUD)
                }
            }

            Section("Sound") {
                SettingRow("Auto-mute during calls",
                           help: MicrophoneMonitor.isSupported
                               ? "Stay silent while the microphone is in use."
                               : "Needs macOS 14.2 or later.") {
                    Toggle("Auto-mute during calls", isOn: $appState.autoMuteDuringCalls)
                        .disabled(!MicrophoneMonitor.isSupported)
                }
            }

            Section("Privacy") {
                SettingRow("Input Monitoring", help: "Needed to hear key presses. We never record what you type.") {
                    if appState.hasInputMonitoringAccess {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.body)
                            .foregroundStyle(.white, .green)
                            // Same width as the switches above, so the tick sits under their center.
                            .frame(width: 44, alignment: .center)
                            .accessibilityLabel("Allowed")
                    } else {
                        Button("Allow in System Settings…") {
                            appState.requestInputMonitoringAccess()
                        }
                        .controlSize(.small)
                    }
                }
            }

            Section {
                Text("Clackwork \(appVersion) · macOS 13 Ventura and later")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
        .formStyle(.grouped)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

/// A settings row: label and help text on the left, a control on the right.
struct SettingRow<Control: View>: View {
    let label: String
    let help: String
    @ViewBuilder let control: () -> Control

    init(_ label: String, help: String, @ViewBuilder control: @escaping () -> Control) {
        self.label = label
        self.help = help
        self.control = control
    }

    var body: some View {
        // An explicit HStack (not LabeledContent) so the control is centered vertically
        // against the two-line label instead of aligned to its first line.
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                Text(help)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            control()
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState(defaults: UserDefaults(suiteName: "preview")!, engine: nil))
        .frame(width: 700, height: 548)
}
