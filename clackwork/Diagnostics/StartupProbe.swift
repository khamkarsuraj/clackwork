import Darwin
import Foundation
import os

/// Measures how soon after launch Clackwork can play a key (NFR: within 1 second, with
/// every profile loaded).
///
/// Off by default. Turn it on with the launch argument `-measureStartup YES`. Each
/// milestone reports the time since the kernel started the process, so dyld and framework
/// loading count too:
///
/// - sounds ready:  every pack decoded and pitch-rendered, audio engine running
/// - listener:      the key tap is on, or why it isn't
/// - menu bar:      the status item has been drawn
///
/// Lines go to the unified log (category `startup`) and to standard output, so they show
/// in Xcode and when the binary is run from Terminal. The process start time is wall
/// clock, the only form the kernel keeps, so a clock adjustment during launch (such as a
/// time sync right after boot) would skew a reading; run it again if a number looks off.
nonisolated enum StartupProbe {
    static let isEnabled = UserDefaults.standard.bool(forKey: "measureStartup")

    private static let logger = Logger(subsystem: "com.surajkhamkar.clackwork", category: "startup")

    /// Logs a milestone with the milliseconds since the process started. The message is
    /// only built when the probe is on.
    static func mark(_ milestone: @autoclosure () -> String) {
        guard isEnabled else { return }
        let line: String
        if let processStart {
            let ms = (Date().timeIntervalSince1970 - processStart) * 1000
            line = String(format: "startup: %@ at %.0f ms", milestone(), ms)
        } else {
            line = "startup: \(milestone()) (process start time unavailable)"
        }
        logger.notice("\(line, privacy: .public)")
        print(line)
        fflush(stdout) // so nothing is lost when the run is cut short from a script
    }

    /// When the kernel started this process, as seconds since 1970, or nil if the kernel
    /// would not say.
    static let processStart: TimeInterval? = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_starttime
        return TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000
    }()
}
