import Foundation
import Testing
@testable import clackwork

/// The latency bench and the reports `scripts/latency_bench.sh` saves and compares (issue #46).
struct LatencyReportTests {
    @Test func summarizesPercentiles() {
        let summary = LatencySummary((1...100).map(Double.init))
        #expect(summary.p50 == 51)
        #expect(summary.p95 == 96)
        #expect(summary.max == 100)
        #expect(summary.text == "p50 51.0 / p95 96.0 / max 100.0")
    }

    @Test func emptySummaryIsZero() {
        #expect(LatencySummary([]) == LatencySummary([0]))
    }

    @Test func benchPatternLooksLikeTyping() {
        let pattern = LatencyBench.pattern
        let letters = pattern.filter { $0 == .standard }.count
        #expect(Set(pattern) == Set(KeyType.allCases), "every key type is exercised")
        #expect(Double(letters) / Double(pattern.count) >= 0.6, "mostly letters, like real typing")
    }

    @Test func reportLineRoundTrips() throws {
        var context = LatencyReport.Context()
        context.outputDevice = "Speakers"
        context.intervalMs = 30
        let report = LatencyReport(kind: "bench", keys: 3,
                                   parts: ["handoff": LatencySummary([0.1, 0.2, 0.3]),
                                           "total": LatencySummary([8.1, 8.2, 8.3])],
                                   audioPathMs: 8, context: context)
        let line = report.line
        #expect(line.hasPrefix(LatencyReport.linePrefix))
        let json = Data(line.dropFirst(LatencyReport.linePrefix.count).utf8)
        let decoded = try JSONDecoder().decode(LatencyReport.self, from: json)
        #expect(decoded.parts == report.parts)
        #expect(decoded.context.outputDevice == "Speakers")
        #expect(!line.contains("\n"), "one line, so a script can pick it out")
    }

    @Test func reportCarriesTimingsOnly() {
        // Adding a field here needs a privacy review: a report must never say which keys were pressed.
        let fields = Mirror(reflecting: LatencyReport(kind: "bench", keys: 0, parts: [:], audioPathMs: 0,
                                                      context: .init())).children.compactMap(\.label)
        #expect(fields == ["kind", "keys", "parts", "audioPathMs", "context"])
    }
}
