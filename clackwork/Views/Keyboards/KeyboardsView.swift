import SwiftUI

/// The Keyboards section: profile cards, the selected keyboard, volume, and a test field.
struct KeyboardsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pressedKeys: Set<KeyboardIllustration.KeyID> = []
    @State private var typedText = ""
    @State private var releaseTasks: [KeyboardIllustration.KeyID: Task<Void, Never>] = [:]
    @State private var previewTask: Task<Void, Never>?
    @State private var previousLength = 0

    var body: some View {
        if appState.isEnabled {
            canvas
        } else {
            SoundOffView()
        }
    }

    private var canvas: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !appState.hasInputMonitoringAccess {
                permissionBanner
            }

            profileGrid

            HStack(alignment: .top, spacing: 28) {
                KeyboardIllustration(
                    palette: appState.selectedProfile.palette(for: colorScheme),
                    pressedKeys: pressedKeys
                )
                .frame(width: 340)
                .onReceive(appState.keyEvents) { event in
                    // Real keys: sink on key down, pop up on key up.
                    guard let location = event.location else { return }
                    releaseTasks[location]?.cancel()
                    releaseTasks[location] = nil
                    if reduceMotion { return }
                    if event.isDown {
                        pressedKeys.insert(location)
                    } else {
                        pressedKeys.remove(location)
                    }
                }
                .onChange(of: appState.isListening) { _ in
                    pressedKeys.removeAll()
                }

                details
            }

            Spacer(minLength: 0)

            tryIt
        }
        .padding(EdgeInsets(top: 20, leading: 24, bottom: 24, trailing: 24))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Shown until Input Monitoring is granted; without it only the Try it field makes sound.
    private var permissionBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard.badge.ellipsis")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Clackwork can't hear your keys in other apps yet.")
                    .font(.callout)
                Text("Allow Input Monitoring in System Settings. We never record what you type.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Allow Input Monitoring…") {
                appState.requestInputMonitoringAccess()
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var profileGrid: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(KeyboardProfile.all) { profile in
                ProfileCard(
                    profile: profile,
                    isSelected: profile == appState.selectedProfile
                ) {
                    appState.selectedProfile = profile
                    appState.play(.standard)
                    press(.random())
                }
            }
        }
    }

    private var details: some View {
        let profile = appState.selectedProfile
        return VStack(alignment: .leading, spacing: 10) {
            Text(profile.family.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Text(profile.name)
                .font(.title2.weight(.semibold))
            // No .fixedSize(horizontal: false, vertical: true) here: inside a
            // NavigationSplitView detail on macOS 26 it collapses the whole canvas.
            Text(profile.description)
                .font(.callout)
                .foregroundStyle(.primary.opacity(0.8))

            Button {
                preview()
            } label: {
                Label("Preview", systemImage: "play.fill")
            }
            .padding(.top, 4)

            volume
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var volume: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Volume")
                Spacer()
                Text("\(Int((appState.volume * 100).rounded()))%")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Slider(value: $appState.volume, in: 0...1) {
                Text("Volume")
            } minimumValueLabel: {
                Image(systemName: "speaker.fill")
            } maximumValueLabel: {
                Image(systemName: "speaker.wave.2.fill")
            }
            .labelsHidden()
            .foregroundStyle(.secondary)
        }
    }

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Try it")
                .font(.caption.weight(.semibold))
            TextField("Type here to hear this keyboard…", text: $typedText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .onChange(of: typedText) { newValue in
                    typed(newValue)
                }
                .onSubmit {
                    guard !appState.isListening else { return }
                    appState.play(.returnKey)
                    press(KeyboardLayout.Location(row: 2, column: 12))
                }
            Text("Nothing you type is stored or sent anywhere.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// Plays a short burst of keys so the user can hear the profile (FR-9).
    private func preview() {
        previewTask?.cancel()
        previewTask = Task {
            let sequence: [KeyType] = [.standard, .standard, .standard, .space, .standard, .standard, .returnKey]
            for key in sequence {
                guard !Task.isCancelled else { return }
                appState.play(key)
                press(key == .space ? .space : .random())
                try? await Task.sleep(nanoseconds: UInt64.random(in: 70_000_000...110_000_000))
            }
        }
    }

    /// Maps a change in the test field to a key type without looking at the characters.
    /// While the system-wide listener runs it already plays the sound, so only animate.
    private func typed(_ newValue: String) {
        defer { previousLength = newValue.count }
        let key: KeyType
        if newValue.count < previousLength {
            key = .backspace
        } else if newValue.last == " " {
            key = .space
        } else {
            key = .standard
        }
        guard !appState.isListening else { return }
        appState.play(key)
        press(key == .space ? .space : .random())
    }

    /// Sinks a key for a moment. Used for mouse-driven sounds (cards, Preview) and for the
    /// test field when the system-wide listener isn't running.
    private func press(_ key: KeyboardIllustration.KeyID) {
        guard !reduceMotion else { return }
        releaseTasks[key]?.cancel()
        pressedKeys.insert(key)
        releaseTasks[key] = Task {
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled else { return }
            pressedKeys.remove(key)
            releaseTasks[key] = nil
        }
    }
}

#Preview("Light") {
    KeyboardsView()
        .environmentObject(AppState(defaults: UserDefaults(suiteName: "preview")!, engine: nil))
        .environmentObject(ShortcutStore(defaults: UserDefaults(suiteName: "preview")!))
        .frame(width: 700, height: 548)
}

#Preview("Dark") {
    KeyboardsView()
        .environmentObject(AppState(defaults: UserDefaults(suiteName: "preview")!, engine: nil))
        .environmentObject(ShortcutStore(defaults: UserDefaults(suiteName: "preview")!))
        .frame(width: 700, height: 548)
        .preferredColorScheme(.dark)
}
