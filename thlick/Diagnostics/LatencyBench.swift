import AppKit
import Foundation

/// A repeatable latency run that needs no typing (issue #46).
///
/// Off by default. Launch with `-latencyBench 1000` to send that many simulated key
/// presses through the same path a real key takes after the event tap: the playback gate,
/// then `SoundEngine.play` on a user-interactive thread. Each press is timed from just
/// before the gate to the sound being scheduled ("handoff", the part the live probe calls
/// the same); "total" adds the worst-case render wait and output latency. The time from the
/// hardware to the tap belongs to macOS and is left to the live `-measureLatency` probe.
///
/// It prints one `LatencyReport` line and quits, exiting with status 1 if no sound pack is
/// loaded, since then nothing would be scheduled. Optional launch arguments:
///
/// - `-latencyBenchInterval 30`: milliseconds between presses (default 30, fast typing)
/// - `-latencyBenchProfile cobalt-clack`: the profile to play (default: the default profile)
/// - `-latencyBenchAudible YES`: play at the saved volume instead of silently
///
/// `scripts/latency_bench.sh` builds Release, runs this and saves the report.
nonisolated enum LatencyBench {
    static let keyCount = UserDefaults.standard.integer(forKey: "latencyBench")
    static var isEnabled: Bool { keyCount > 0 }

    /// Presses before measuring starts, so first-use costs don't count.
    static let warmUpKeys = 20

    /// A fixed mix of keys close to ordinary typing, repeated in order so every run plays
    /// the same sequence: mostly letters, a space every few keys, and the occasional
    /// backspace, return and modifier.
    static let pattern: [KeyType] = [
        .standard, .standard, .standard, .standard, .space,
        .standard, .standard, .modifier, .standard, .standard, .space,
        .standard, .standard, .standard, .backspace, .standard, .space,
        .standard, .standard, .returnKey,
    ]

    /// Starts the run on its own thread. Called once the engine has loaded every pack.
    static func start(engine: SoundEngine?) {
        let defaults = UserDefaults.standard
        let interval = defaults.double(forKey: "latencyBenchInterval") > 0 ? defaults.double(forKey: "latencyBenchInterval") : 30
        let profileID = defaults.string(forKey: "latencyBenchProfile") ?? KeyboardProfile.defaultProfile.id

        guard let engine, engine.loadedProfileIDs.contains(profileID) else {
            fail("no sound pack loaded for \(profileID); the bench needs the packs in thlick/Sounds")
        }
        if !defaults.bool(forKey: "latencyBenchAudible") { engine.volume = 0 }

        let gate = PlaybackGate()
        gate.update(isEnabled: true, profileID: profileID)
        let thread = Thread {
            var handoff: [Double] = []
            handoff.reserveCapacity(keyCount)
            for index in 0..<(warmUpKeys + keyCount) {
                let key = pattern[index % pattern.count]
                // The same steps as the listener's key-down handler.
                let start = LatencyProbe.now()
                if let profile = gate.profileToPlay { engine.play(key, profileID: profile) }
                let end = LatencyProbe.now()
                if index >= warmUpKeys { handoff.append(Double(end - start) / 1_000_000) }
                Thread.sleep(forTimeInterval: interval / 1000)
            }
            finish(engine: engine, handoff: handoff, profileID: profileID, intervalMs: interval)
        }
        thread.qualityOfService = .userInteractive
        thread.name = "latency-bench"
        thread.start()
    }

    private static func finish(engine: SoundEngine, handoff: [Double], profileID: String, intervalMs: Double) {
        let audioPath = engine.audioPathLatencyMs
        var context = LatencyReport.Context()
        context.outputDevice = engine.outputDeviceName
        context.deviceSampleRate = engine.outputDeviceSampleRate
        context.ioBufferFrames = engine.ioBufferFrames
        context.outputLatencyMs = engine.outputLatency * 1000
        context.profile = profileID
        context.intervalMs = intervalMs
        let report = LatencyReport(
            kind: "bench", keys: handoff.count,
            parts: ["handoff": LatencySummary(handoff), "total": LatencySummary(handoff.map { $0 + audioPath })],
            audioPathMs: audioPath, context: context
        )
        print(report.line)
        fflush(stdout)
        exit(0)
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("latency-bench: \(message)\n".utf8))
        exit(1)
    }
}
