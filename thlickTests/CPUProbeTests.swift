import Testing
@testable import thlick

/// NFR CPU (issue #33): the probe that measures idle and typing CPU must file each second correctly.
struct CPUProbeTests {
    typealias Tally = CPUProbe.Tally

    @Test func quietSecondsCountAsIdle() {
        var tally = Tally()
        for _ in 0..<5 { #expect(tally.add(cpu: 0.005, wall: 1, keys: 0) == nil) }
        #expect(tally.idle.wall == 5)
        #expect(abs(tally.idle.percent - 0.5) < 0.0001)
        #expect(tally.settling.wall == 0)
        #expect(tally.typing.wall == 0)
    }

    @Test func secondsWithKeysCountAsTyping() {
        var tally = Tally()
        for _ in 0..<4 { _ = tally.add(cpu: 0.02, wall: 1, keys: 3) }
        #expect(tally.typing == Tally.Bucket(cpu: 0.08, wall: 4, keys: 12))
        #expect(abs(tally.typing.percent - 2) < 0.0001)
    }

    @Test func secondsJustAfterTypingCountAsSettlingThenIdle() {
        var tally = Tally()
        _ = tally.add(cpu: 0.02, wall: 1, keys: 1)
        for _ in 0..<(Tally.idleAfter + 2) { _ = tally.add(cpu: 0.01, wall: 1, keys: 0) }
        // The first idleAfter - 1 quiet seconds settle; from idleAfter on it's idle.
        #expect(tally.settling.wall == Double(Tally.idleAfter - 1))
        #expect(tally.idle.wall == 3)
    }

    @Test func reportsEveryFifteenTicksAndStartsOver() throws {
        var tally = Tally()
        for _ in 0..<(Tally.reportEvery - 1) { #expect(tally.add(cpu: 0.005, wall: 1, keys: 0) == nil) }
        let report = tally.add(cpu: 0.005, wall: 1, keys: 0)
        let line = try #require(report)
        #expect(line == "cpu over 15 s | idle 0.50% over 15 s | settling no samples | typing no samples")
        #expect(tally.idle.wall == 0)
    }

    @Test func reportIncludesTypingRate() throws {
        var tally = Tally()
        var line: String?
        for _ in 0..<Tally.reportEvery { line = tally.add(cpu: 0.02, wall: 1, keys: 4) }
        let report = try #require(line)
        #expect(report.hasSuffix("typing 2.00% over 15 s, 4.0 keys/s"))
    }
}
