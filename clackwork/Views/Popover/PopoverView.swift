import SwiftUI

/// The menu bar popover: on/off, keyboard picker, volume, mute and the footer (FR-17).
/// Every control writes straight to `AppState`, so changes apply immediately (FR-18).
struct PopoverView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    /// Opens the main window, on a given section when one is passed.
    let openWindow: (SidebarSection?) -> Void

    /// Opacity for controls that do nothing while sound is off.
    private var dimmed: Double { appState.isEnabled ? 1 : 0.45 }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            header
            divider.padding(.horizontal, 10)

            keyboards
            divider.padding(.horizontal, 10).padding(.vertical, 4)

            volume
            mute
            divider.padding(EdgeInsets(top: 0, leading: 10, bottom: 3, trailing: 10))

            footer
        }
        .padding(5)
        .frame(width: 280)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(height: 0.5)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Clackwork")
                    .font(.system(size: 13, weight: .semibold))
                status
            }
            Spacer()
            Toggle("Sound", isOn: $appState.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel("Sound")
        }
        .padding(EdgeInsets(top: 5, leading: 10, bottom: 7, trailing: 10))
    }

    @ViewBuilder
    private var status: some View {
        if appState.isEnabled, appState.isMuted, let endsAt = appState.muteEndsAt {
            // Ticks only while the popover is on screen.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                statusText("Muted · \(Self.remaining(until: endsAt, from: context.date)) left", muted: true)
            }
        } else if appState.isEnabled, appState.isMuted {
            statusText("Muted until you unmute", muted: true)
        } else if appState.isEnabled, appState.isAutoMuted {
            statusText("Muted while the microphone is in use", muted: true)
        } else if appState.isEnabled, !appState.hasInputMonitoringAccess {
            statusText("Waiting for Input Monitoring", muted: false)
        } else if appState.isEnabled {
            statusText("Playing · \(appState.selectedProfile.name)", muted: false)
        } else {
            statusText("Off", muted: false)
        }
    }

    private func statusText(_ text: String, muted: Bool) -> some View {
        Text(text)
            .font(.system(size: 11, weight: muted ? .medium : .regular))
            .foregroundStyle(muted ? AnyShapeStyle(Self.mutedColor) : AnyShapeStyle(.secondary))
            .lineLimit(1)
    }

    /// Dark orange in light mode for contrast on the pale popover, system orange in dark mode.
    private static let mutedColor = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .systemOrange : NSColor(Color(hex: 0xB4430E))
    })

    /// Time left on a timed mute, rounded up to the minute: "14 min", "1 hr".
    static func remaining(until end: Date, from now: Date) -> String {
        let minutes = max(1, Int((end.timeIntervalSince(now) / 60).rounded(.up)))
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .short
        return formatter.string(from: TimeInterval(minutes * 60)) ?? "\(minutes) min"
    }

    // MARK: Keyboard picker

    private var keyboards: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Keyboard")
                .padding(EdgeInsets(top: 6, leading: 10, bottom: 2, trailing: 10))

            ForEach(KeyboardProfile.all) { profile in
                let isSelected = profile == appState.selectedProfile
                Button {
                    appState.selectedProfile = profile
                    appState.play(.standard)
                } label: {
                    HStack(spacing: 8) {
                        IconWell(isOn: isSelected, onColor: profile.palette(for: colorScheme).accent) {
                            Image(nsImage: Self.switchGlyph)
                                .resizable()
                                .frame(width: 15, height: 15)
                        }
                        Text(profile.name)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 4)
                        Text(profile.family)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 13))
                    .frame(height: 30)
                }
                .buttonStyle(RowButtonStyle())
                .opacity(dimmed)
                .accessibilityLabel(profile.name)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    /// The menu bar switch, reused in the keyboard rows' icon wells.
    private static let switchGlyph = MenuBarIcon.image(for: .on)

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    // MARK: Volume

    private var volume: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                sectionLabel("Volume")
                Spacer()
                Text("\(Int((appState.volume * 100).rounded()))%")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $appState.volume, in: 0...1) {
                Text("Volume")
            } minimumValueLabel: {
                Image(systemName: "speaker.fill")
            } maximumValueLabel: {
                Image(systemName: "speaker.wave.2.fill")
            }
            .labelsHidden()
            .controlSize(.small)
            .foregroundStyle(.secondary)
        }
        .padding(EdgeInsets(top: 2, leading: 10, bottom: 6, trailing: 10))
        .opacity(dimmed)
    }

    // MARK: Mute (FR-13)

    private static let timedMutes: [(title: String, duration: TimeInterval?)] = [
        ("For 15 minutes", 15 * 60),
        ("For 1 hour", 60 * 60),
        ("Until I unmute", nil),
    ]

    private var mute: some View {
        ZStack(alignment: .trailing) {
            Button {
                appState.toggleMute()
            } label: {
                HStack(spacing: 8) {
                    IconWell(isOn: appState.isMuted) {
                        Image(systemName: "speaker.slash.fill")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    Text(appState.isMuted ? "Unmute" : "Mute")
                    Spacer()
                }
                .font(.system(size: 13))
                .frame(height: 30)
            }
            .buttonStyle(RowButtonStyle())

            Menu {
                Section("Mute") {
                    ForEach(Self.timedMutes, id: \.title) { option in
                        Toggle(option.title, isOn: Binding(
                            get: { appState.isMuted && appState.muteDuration == option.duration },
                            set: { _ in appState.mute(for: option.duration) }
                        ))
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.trailing, 10)
            .accessibilityLabel("Timed mute options")
        }
        .padding(.bottom, 2)
        // Muting means nothing while sound is off.
        .disabled(!appState.isEnabled)
        .opacity(dimmed)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 0) {
            footerRow("Open Clackwork") { openWindow(nil) }
            footerRow("Settings") { openWindow(.settings) }
            footerRow("Quit") { NSApp.terminate(nil) }
        }
    }

    private func footerRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .frame(height: 24)
        }
        .buttonStyle(RowButtonStyle())
    }
}

/// A full-width row with a soft grey hover, like the rows in the system's AirPods and Sound menus.
private struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        let configuration: Configuration
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(fillOpacity))
                }
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
        }

        private var fillOpacity: Double {
            guard isEnabled else { return 0 }
            return configuration.isPressed ? 0.12 : (isHovered ? 0.07 : 0)
        }
    }
}

/// A round icon well: grey normally, filled with `onColor` and a white icon when on.
private struct IconWell<Icon: View>: View {
    let isOn: Bool
    var onColor: Color = .accentColor
    @ViewBuilder let icon: Icon

    var body: some View {
        icon
            .foregroundStyle(isOn ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
            .frame(width: 24, height: 24)
            .background(Circle().fill(isOn ? onColor : Color.primary.opacity(0.1)))
    }
}

#Preview {
    PopoverView { _ in }
        .environmentObject(AppState(defaults: UserDefaults(suiteName: "preview")!, engine: nil))
}
