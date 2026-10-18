import Darwin
import Foundation
import os

/// Measures the app's own CPU use while idle and while typing (NFR: under 1% idle, under 5%
/// during sustained fast typing).
///
/// Off by default. Turn it on with the launch argument `-measureCPU YES`. It counts key
/// presses only, never which key was pressed. Once a second it reads the process's CPU time
/// and files that second under one of three buckets:
///
/// - typing:   at least one key was pressed during the second
/// - settling: no key this second, but one within the last `idleAfter` seconds, while
///             trailing sounds and key-up animations finish
/// - idle:     no key for at least `idleAfter` seconds
///
/// The first `warmUp` seconds after launch are skipped, so startup work doesn't count as idle.
/// Every 15 seconds it logs each bucket's average, as a percentage of one core (the same
/// scale as Activity Monitor), plus the typing rate.
nonisolated final class CPUProbe: @unchecked Sendable {
    static let isEnabled = UserDefaults.standard.bool(forKey: "measureCPU")

    private static let logger = Logger(subsystem: "com.surajkhamkar.clackwork", category: "cpu")
    private static let tick: TimeInterval = 1
    private static let warmUp: TimeInterval = 10

    /// Key presses since the last tick. Written on the key listener thread.
    private let pendingKeys = OSAllocatedUnfairLock(initialState: 0)

    // Everything below is touched only on `queue`.
    private let queue = DispatchQueue(label: "com.surajkhamkar.clackwork.cpu-probe", qos: .utility)
    private var timer: DispatchSourceTimer?
    /// Readings at the previous tick; nil until the warm-up ends.
    private var last: (cpu: Double, wall: Double)?
    private var tally = Tally()

    init() {
        queue.async { [self] in
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + Self.warmUp, repeating: Self.tick, leeway: .milliseconds(100))
            timer.setEventHandler { [weak self] in self?.sample() }
            timer.resume()
            self.timer = timer
        }
    }

    deinit { timer?.cancel() }

    /// Counts one key press. Safe to call from any thread.
    func keyPressed() {
        pendingKeys.withLock { $0 += 1 }
    }

    private func sample() {
        let cpu = Self.processCPUSeconds()
        let wall = Self.uptimeSeconds()
        let keys = pendingKeys.withLock { count in
            defer { count = 0 }
            return count
        }
        defer { last = (cpu, wall) }
        guard let last else { return }
        if let line = tally.add(cpu: cpu - last.cpu, wall: wall - last.wall, keys: keys) {
            Self.logger.notice("\(line, privacy: .public)")
        }
    }

    /// Files each tick under idle, settling or typing, and produces a report line every
    /// `reportEvery` ticks. Pure bookkeeping, separate from the clock so it can be tested.
    struct Tally {
        static let reportEvery = 15
        static let idleAfter = 5

        struct Bucket: Equatable {
            var cpu: Double = 0
            var wall: Double = 0
            var keys = 0

            var percent: Double { wall > 0 ? cpu / wall * 100 : 0 }
        }

        private(set) var idle = Bucket()
        private(set) var settling = Bucket()
        private(set) var typing = Bucket()
        private var secondsSinceKey = Int.max
        private var ticks = 0

        /// Records one tick: CPU seconds used and wall seconds elapsed since the previous
        /// tick, and key presses during it. Returns a report line when one is due, then
        /// starts the next report from zero.
        mutating func add(cpu: Double, wall: Double, keys: Int) -> String? {
            secondsSinceKey = keys > 0 ? 0 : (secondsSinceKey == .max ? .max : secondsSinceKey + 1)
            if keys > 0 {
                typing.cpu += cpu
                typing.wall += wall
                typing.keys += keys
            } else if secondsSinceKey >= Self.idleAfter {
                idle.cpu += cpu
                idle.wall += wall
            } else {
                settling.cpu += cpu
                settling.wall += wall
            }

            ticks += 1
            guard ticks >= Self.reportEvery else { return nil }
            let line = "cpu over \(ticks) s | idle \(Self.describe(idle)) | settling \(Self.describe(settling))"
                + " | typing \(Self.describe(typing))"
                + (typing.wall > 0 ? String(format: ", %.1f keys/s", Double(typing.keys) / typing.wall) : "")
            ticks = 0
            idle = Bucket()
            settling = Bucket()
            typing = Bucket()
            return line
        }

        /// "1.23% over 22 s", or "no samples".
        private static func describe(_ bucket: Bucket) -> String {
            bucket.wall > 0 ? String(format: "%.2f%% over %.0f s", bucket.percent, bucket.wall) : "no samples"
        }
    }

    /// User plus system CPU time used by this process so far, in seconds.
    private static func processCPUSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func seconds(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    private static func uptimeSeconds() -> Double {
        Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1_000_000_000
    }
}
