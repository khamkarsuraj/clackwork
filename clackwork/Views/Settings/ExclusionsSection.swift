import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Exclusions: the apps where sound never plays while they are in front (FR-16).
/// Laid out like System Settings' Login Items list: rows with the app icon, and a + / −
/// bar underneath.
struct ExclusionsSection: View {
    @EnvironmentObject private var exclusions: ExclusionStore
    @State private var selection: ExcludedApp.ID?

    var body: some View {
        Section {
            VStack(spacing: 0) {
                if exclusions.apps.isEmpty {
                    Text("No apps excluded")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    List(selection: $selection) {
                        ForEach(exclusions.apps) { app in
                            HStack(spacing: 8) {
                                Image(nsImage: app.icon)
                                    .resizable()
                                    .frame(width: 20, height: 20)
                                Text(app.name)
                                Spacer()
                            }
                            .padding(.vertical, 1)
                            .tag(app.id)
                            .accessibilityLabel(app.name)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .frame(height: max(160, CGFloat(exclusions.apps.count) * 28 + 8))
                }
                Divider()
                HStack(spacing: 0) {
                    Button(action: addApps) {
                        Image(systemName: "plus")
                            .frame(width: 24, height: 20)
                    }
                    .accessibilityLabel("Add app")
                    .help("Choose an app to exclude")
                    Divider().frame(height: 14)
                    Button(action: removeSelected) {
                        Image(systemName: "minus")
                            .frame(width: 24, height: 20)
                    }
                    .disabled(selection == nil)
                    .accessibilityLabel("Remove app")
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(2)
            }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
            .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
        } header: {
            Text("Sound never plays while you are working in one of these apps. Everything else is unaffected.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .textCase(nil)
                .padding(.bottom, 4)
        } footer: {
            Text("Click + to choose apps from your Applications folder. Changes apply at once, even to the app in front.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
    }

    private func addApps() {
        let panel = NSOpenPanel()
        panel.title = "Choose apps to exclude"
        panel.prompt = "Exclude"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let app = ExcludedApp(url: url) { exclusions.add(app) }
        }
    }

    private func removeSelected() {
        guard let selection, let app = exclusions.apps.first(where: { $0.id == selection }) else { return }
        exclusions.remove(app)
        self.selection = nil
    }
}
