import SwiftUI

/// First-launch onboarding, shown in the main window until it is finished or skipped
/// (FR-20 to FR-24): welcome, Input Monitoring, pick a keyboard, all done.
struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model: OnboardingModel

    init(appState: AppState) {
        _model = StateObject(wrappedValue: OnboardingModel(appState: appState))
    }

    /// For snapshots that start on a given step.
    init(model: OnboardingModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.step {
                case .welcome: welcome
                case .permission: permission
                case .keyboard: keyboard
                case .finish: finish
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)

            Divider()
            footer
        }
        .frame(maxWidth: 640, maxHeight: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.step)
    }

    // MARK: Step 1: welcome (FR-21)

    private var welcome: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .accessibilityHidden(true)
            Text("Welcome to Thlick")
                .font(.system(size: 26, weight: .bold))
                .padding(.top, 4)
            Text("Hear a real mechanical keyboard every time you type, in any app on your Mac.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .padding(.horizontal, 64)
    }

    // MARK: Step 2: Input Monitoring (FR-21, FR-22)

    private var permission: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 32) {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 44, height: 44)
                        .background(Color.accentColor.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .accessibilityHidden(true)
                    Text("Allow Input Monitoring")
                        .font(.title2.weight(.bold))
                    Text("macOS needs your OK before any app can notice key presses. Thlick only learns which kind of key you pressed, so it can play the right sound.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 8) {
                        promise("We never record or store what you type.")
                        promise("Key events never leave your Mac.")
                        promise("Password fields stay silent.")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SystemSettingsHint()
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Waiting for permission… this step continues on its own.")
                }
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
                Spacer()
                // macOS can hold a new grant back until the app restarts.
                Text("Already turned it on?")
                    .foregroundStyle(.secondary)
                Button("Quit & Reopen") { model.relaunch() }
                    .buttonStyle(.link)
            }
            .font(.caption)
            .padding(.bottom, 14)
        }
        .padding(.horizontal, 40)
    }

    private func promise(_ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "checkmark")
                .font(.body.weight(.bold))
                .foregroundStyle(.green)
        }
    }

    // MARK: Step 3: pick a keyboard (FR-23)

    private var keyboard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pick your keyboard")
                    .font(.title2.weight(.bold))
                Text("Click one to hear it. You can change it any time from the menu bar.")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(Array(KeyboardProfile.all.enumerated()), id: \.element.id) { index, profile in
                    ProfileRow(profile: profile, isSelected: profile == appState.selectedProfile) {
                        appState.selectedProfile = profile
                        appState.play(.standard)
                    }
                    if index < KeyboardProfile.all.count - 1 {
                        Divider()
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Keyboard profile")

            Spacer(minLength: 0)

            // Where the permission step said it was waiting, so the two read as one.
            if appState.hasInputMonitoringAccess {
                Label("Input Monitoring allowed", systemImage: "checkmark")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
                    .padding(.bottom, 14)
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 20)
    }

    // MARK: Step 4: all done, and where Thlick lives (FR-24)

    private var finish: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.white, .green)
                .accessibilityHidden(true)
            Text("You’re all set")
                .font(.system(size: 26, weight: .bold))
            VStack(spacing: 10) {
                MenuBarHint()
                    .frame(width: 360)
                Text("Thlick lives in your menu bar. Click its icon to switch profiles, change volume or mute.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 64)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            StepDots(current: model.step)
            Spacer()
            if model.canSkip {
                Button("Skip setup") { model.skip() }
                    .buttonStyle(.link)
                    .padding(.horizontal, 10)
            }
            switch model.step {
            case .welcome:
                Button("Get started") { model.next() }
                    .keyboardShortcut(.defaultAction)
            case .permission:
                Button("Back") { model.back() }
                Button("Open System Settings") { model.requestAccess() }
                    .keyboardShortcut(.defaultAction)
            case .keyboard:
                Button("Continue") { model.next() }
                    .keyboardShortcut(.defaultAction)
            case .finish:
                Button("Back") { model.back() }
                Button("Start typing") { model.next() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 24)
        .frame(height: 64)
    }
}

/// "Step 2 of 4" as a row of dots, the current one stretched.
private struct StepDots: View {
    let current: OnboardingModel.Step

    var body: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingModel.Step.allCases, id: \.self) { step in
                Capsule()
                    .fill(step.rawValue <= current.rawValue ? Color.accentColor : Color.primary.opacity(0.18))
                    .frame(width: step == current ? 18 : 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current.rawValue + 1) of \(OnboardingModel.Step.allCases.count)")
    }
}

/// One profile in the step 3 list, chosen like a radio button.
private struct ProfileRow: View {
    let profile: KeyboardProfile
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                RoundedRectangle(cornerRadius: 3)
                    .fill(profile.palette(for: colorScheme).accent)
                    .frame(width: 10, height: 10)
                Text(profile.name)
                    .fontWeight(isSelected ? .semibold : .regular)
                Spacer()
                Text(profile.family)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(profile.name)
        .accessibilityValue(profile.family)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A sketch of the Input Monitoring list in System Settings, with Thlick switched on.
private struct SystemSettingsHint: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("System Settings › Privacy & Security")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Input Monitoring")
                .font(.callout.weight(.semibold))
            VStack(spacing: 0) {
                row(icon: Color.primary.opacity(0.18), name: "Other app", on: false)
                Divider()
                row(icon: Color(hex: 0x3B3B3D), name: "Thlick", on: true)
                    .background(Color.accentColor.opacity(0.12))
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
            Text("Turn on Thlick, then come back.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 220)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        // The words are said in full on the left; this only shows where the switch is.
        .accessibilityHidden(true)
    }

    private func row(icon: Color, name: String, on: Bool) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 5).fill(icon).frame(width: 18, height: 18)
            Text(name)
                .font(.caption.weight(on ? .semibold : .regular))
                .foregroundStyle(on ? .primary : .secondary)
            Spacer()
            Capsule()
                .fill(on ? Color.accentColor : Color.primary.opacity(0.18))
                .frame(width: 26, height: 15)
                .overlay(alignment: on ? .trailing : .leading) {
                    Circle().fill(.white).frame(width: 12, height: 12).padding(1.5)
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

/// A sketch of the menu bar with Thlick's icon picked out.
private struct MenuBarHint: View {
    var body: some View {
        HStack(spacing: 14) {
            Spacer()
            placeholder(width: 40)
            placeholder(width: 28)
            Image(nsImage: MenuBarIcon.image(for: .on))
                .renderingMode(.template)
                .foregroundStyle(.primary)
                .frame(width: 30, height: 22)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.accentColor, lineWidth: 2))
            placeholder(width: 36)
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }

    private func placeholder(width: CGFloat) -> some View {
        Capsule().fill(Color.primary.opacity(0.15)).frame(width: width, height: 6)
    }
}

#Preview {
    let state = AppState(defaults: UserDefaults(suiteName: "preview")!, engine: nil)
    OnboardingView(appState: state)
        .environmentObject(state)
        .frame(width: 720, height: 520)
}
