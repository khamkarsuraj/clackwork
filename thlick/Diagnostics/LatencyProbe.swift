import Foundation
import os

/// Measures the software part of key press to sound latency (NFR: under 20 ms, target 10 ms).
///
/// Off by default. Turn it on with the launch argument `-measureLatency YES`
/// (Xcode: Edit Scheme > Run > Arguments). It records timestamps only, never which key
/// was pressed. Every 100 key presses it logs a summary to the console:
///
/// - delivery: hardware key event to the event-tap callback
/// - handoff:  tap callback to the sound being scheduled
/// - audio:    worst-case wait for the next audio cycle plus the output device latency
/// - total:    delivery + handoff + audio
///
/// Each summary is also logged and printed as a JSON `LatencyReport`, which
/// `scripts/latency_bench.sh --compare` can compare against another run.
/// Only ever called from the key listener thread, so it needs no locking.
nonisolated final class LatencyProbe: @unchecked Sendable {
    static let isEnabled = UserDefaults.standard.bool(forKey: "measureLatency")

    private static let logger = Logger(subsystem: "com.surajkhamkar.thlick", category: "latency")
    private static let reportEvery = 100

    private var delivery: [Double] = []
    private var handoff: [Double] = []
    private var total: [Double] = []

    /// Records one key press. All times are in nanoseconds on the uptime clock.
    func record(eventNanos: UInt64, tapNanos: UInt64, scheduledNanos: UInt64, audioPathMs: Double) {
        let d = Self.ms(from: eventNanos, to: tapNanos)
        let h = Self.ms(from: tapNanos, to: scheduledNanos)
        delivery.append(d)
        handoff.append(h)
        total.append(d + h + audioPathMs)

        guard total.count >= Self.reportEvery else { return }
        let summaries = ["delivery": LatencySummary(delivery), "handoff": LatencySummary(handoff),
                         "total": LatencySummary(total)]
        let line = "latency over \(total.count) keys (ms) | "
            + "delivery \(summaries["delivery"]!.text) | handoff \(summaries["handoff"]!.text) | "
            + "audio \(String(format: "%.1f", audioPathMs)) | total \(summaries["total"]!.text)"
        Self.logger.notice("\(line, privacy: .public)")
        let report = LatencyReport(kind: "live", keys: total.count, parts: summaries,
                                   audioPathMs: audioPathMs, context: .init()).line
        Self.logger.notice("\(report, privacy: .public)")
        print(report)
        fflush(stdout)
        delivery.removeAll(keepingCapacity: true)
        handoff.removeAll(keepingCapacity: true)
        total.removeAll(keepingCapacity: true)
    }

    static func now() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }

    /// CGEvent timestamps are mach ticks on some Macs and nanoseconds on others.
    /// Picks the reading that lands just before `now`.
    static func eventNanos(fromTimestamp timestamp: UInt64, now: UInt64) -> UInt64 {
        let fromTicks = timestamp &* UInt64(timebase.numer) / UInt64(timebase.denom)
        let candidates = [timestamp, fromTicks].filter { $0 <= now && now - $0 < 1_000_000_000 }
        return candidates.max() ?? now
    }

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    private static func ms(from start: UInt64, to end: UInt64) -> Double {
        end > start ? Double(end - start) / 1_000_000 : 0
    }
}
