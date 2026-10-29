import Testing
@testable import thlick

/// The direct-download and App Store builds share code; only the App Store target sets `APP_STORE` (#78).
struct DistributionTests {
    @Test func directDownloadBuildIsNotTheAppStoreBuild() {
        #expect(!Distribution.isAppStore)
    }
}
