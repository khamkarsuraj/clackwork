import Foundation

/// p50, p95 and max of a set of latencies, in milliseconds.
nonisolated struct LatencySummary: Codable, Equatable, Sendable {
    let p50: Double
    let p95: Double
    let max: Double

    init(_ values: [Double]) {
        let sorted = values.sorted()
        func pct(_ p: Double) -> Double {
            sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))]
        }
        p50 = pct(0.5)
        p95 = pct(0.95)
        max = sorted.last ?? 0
    }

    /// "p50 x / p95 y / max z"
    var text: String { String(format: "p50 %.1f / p95 %.1f / max %.1f", p50, p95, max) }
}

/// One latency measurement, as written for `scripts/latency_bench.sh` to save and compare
/// between builds (issue #46). It holds timings and the setup they were taken on, never
/// which keys were pressed.
nonisolated struct LatencyReport: Codable, Sendable {
    /// "bench" for `-latencyBench`, "live" for the `-measureLatency` probe.
    let kind: String
    let keys: Int
    /// Per part: "delivery" (live only), "handoff", "total".
    let parts: [String: LatencySummary]
    /// Worst-case render wait plus output latency, added to every key's total.
    let audioPathMs: Double
    let context: Context

    /// What the numbers depend on, so two reports are only compared like for like.
    struct Context: Codable, Sendable {
        var appVersion = LatencyReport.appVersion
        var configuration = LatencyReport.configuration
        var macModel = LatencyReport.macModel
        var macOS = ProcessInfo.processInfo.operatingSystemVersionString
        var outputDevice: String?
        var deviceSampleRate: Double?
        var ioBufferFrames: UInt32?
        var outputLatencyMs: Double?
        var profile: String?
        /// Time between simulated key presses (bench only).
        var intervalMs: Double?
    }

    /// The prefix the report line is printed with, so a script can pick it out of the output.
    static let linePrefix = "latency-report: "

    /// The report as one line of JSON, with keys sorted so reports diff cleanly.
    var line: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return Self.linePrefix + json
    }

    static let appVersion: String = {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }()

    static let configuration: String = {
        #if DEBUG
        "Debug"
        #else
        "Release"
        #endif
    }()

    /// The Mac's model identifier, such as "Mac15,6".
    static let macModel: String = {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }()
}
