import Foundation
import Testing
@testable import thlick

/// Startup probe (issue #36): the clock it measures from.
struct StartupProbeTests {
    @Test func processStartComesFromTheKernelAndIsRecent() throws {
        let now = Date().timeIntervalSince1970
        let start = try #require(StartupProbe.processStart)
        #expect(start <= now)
        // The test host launched moments ago; a bogus reading would be 0 or far off.
        #expect(now - start < 600)
    }

    @Test func markingNeverThrowsOrCrashes() {
        // Whether the probe is on (scheme argument) or off, a mark must be harmless.
        StartupProbe.mark("test milestone")
    }
}
