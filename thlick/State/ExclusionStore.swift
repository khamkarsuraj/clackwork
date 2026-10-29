import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

/// An app where sound never plays while it is in front (FR-16).
struct ExcludedApp: Identifiable, Hashable, Codable {
    let bundleID: String
    /// Display name as it was when added; the icon is looked up live.
    var name: String

    var id: String { bundleID }

    /// Reads the identifier and name from an app bundle, or nil if it isn't one. The name
    /// is the one Finder shows, localized and without the extension.
    init?(url: URL) {
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { return nil }
        self.init(bundleID: bundleID, name: FileManager.default.displayName(atPath: url.path))
    }

    init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }

    /// The app's icon as installed now, or the generic app icon if it isn't installed.
    /// Looked up once per bundle ID: rows are re-evaluated on every list change.
    var icon: NSImage {
        if let cached = Self.icons[bundleID] { return cached }
        let icon: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            icon = NSWorkspace.shared.icon(for: .applicationBundle)
        }
        Self.icons[bundleID] = icon
        return icon
    }

    private static var icons: [String: NSImage] = [:]
}

/// The user's exclusion list, persisted as JSON in UserDefaults. Order is the order added.
final class ExclusionStore: ObservableObject {
    private static let key = "excludedApps"

    @Published private(set) var apps: [ExcludedApp] {
        didSet { save() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([ExcludedApp].self, from: data) {
            apps = saved
        } else {
            apps = []
        }
    }

    /// Adds an app unless it is already listed.
    func add(_ app: ExcludedApp) {
        guard !apps.contains(where: { $0.bundleID == app.bundleID }) else { return }
        apps.append(app)
    }

    func remove(_ app: ExcludedApp) {
        apps.removeAll { $0.bundleID == app.bundleID }
    }

    func contains(bundleID: String) -> Bool {
        apps.contains { $0.bundleID == bundleID }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(apps) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
