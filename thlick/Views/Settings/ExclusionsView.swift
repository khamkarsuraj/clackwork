import SwiftUI

/// The Exclusions section: the apps where sound never plays while they are in front (FR-16).
struct ExclusionsView: View {
    var body: some View {
        Form {
            ExclusionsSection()
        }
        .formStyle(.grouped)
    }
}

#Preview {
    ExclusionsView()
        .environmentObject(ExclusionStore(defaults: UserDefaults(suiteName: "preview")!))
        .frame(width: 700, height: 548)
}
