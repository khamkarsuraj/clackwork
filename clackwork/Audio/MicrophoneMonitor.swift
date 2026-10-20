import AppKit
import Combine
import CoreAudio
import Foundation

/// Whether any app is capturing from a microphone, for auto-mute during calls (FR-15).
///
/// Asks CoreAudio which processes are running audio input. Nothing is captured and no
/// microphone permission is involved: only the HAL's own bookkeeping is read.
///
/// The answer is re-read every second while watching. Property listeners are registered
/// too, but in practice CoreAudio does not deliver changes of a process's input state to
/// them (observed on macOS 26: a call starting after launch never fired one), so the poll
/// is what makes a call noticed. A read is a handful of cheap HAL property queries.
///
/// Needs the per-process properties of macOS 14.2 and later (`isSupported`). The older
/// device-level signal can't tell a call from Clackwork's own output on a headset, or from
/// Siri listening for its wake word, so auto-mute is unavailable rather than wrong there.
@MainActor
final class MicrophoneMonitor: ObservableObject {
    @Published private(set) var isInUse = false

    /// Whether this macOS can say which processes capture audio (14.2 and later).
    nonisolated static let isSupported: Bool = processes() != nil

    /// How often the HAL is re-read while watching.
    static let pollInterval: TimeInterval = 1

    /// False for tests: never asks the HAL, so results don't depend on the machine.
    private let isLive: Bool
    private var isListening = false
    private var poll: Timer?
    /// Objects with a property listener on them right now.
    private var watched: Set<Watched> = []

    private struct Watched: Hashable {
        let object: AudioObjectID
        let selector: AudioObjectPropertySelector
    }

    private static let ownPID = getpid()
    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    /// Nonisolated so it can be a default argument; it only stores the flag.
    nonisolated init(live: Bool = true) {
        isLive = live
    }

    deinit {
        poll?.invalidate()
        for item in watched { Self.removeListener(item, from: self) }
    }

    /// Starts watching. Does nothing until called, so the setting controls the cost.
    func start() {
        guard !isListening else { return }
        isListening = true
        refresh()
        guard isLive else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = Self.pollInterval * 0.2
        poll = timer
    }

    func stop() {
        guard isListening else { return }
        isListening = false
        poll?.invalidate()
        poll = nil
        for item in watched { Self.removeListener(item, from: self) }
        watched.removeAll()
        set(false)
    }

    /// Whether the periodic read is running, for tests.
    var isPolling: Bool { poll != nil }

    /// For tests on a non-live monitor: stands in for a call starting or ending.
    func simulate(inUse: Bool) {
        guard !isLive else { return }
        set(inUse)
    }

    /// Re-reads the HAL and updates `isInUse`, re-arming listeners for the objects seen.
    func refresh() {
        guard isListening, isLive, let processes = Self.processes() else { return }
        set(Self.anyRunningInput(processes, ownPID: Self.ownPID))

        var wanted = Set(processes.map { Watched(object: $0.object, selector: kAudioProcessPropertyIsRunningInput) })
        wanted.insert(Watched(object: Self.systemObject, selector: kAudioHardwarePropertyProcessObjectList))
        for item in watched.subtracting(wanted) {
            Self.removeListener(item, from: self)
            watched.remove(item)
        }
        for item in wanted.subtracting(watched) where Self.addListener(item, to: self) {
            watched.insert(item)
        }
    }

    private func set(_ inUse: Bool) {
        if inUse != isInUse { isInUse = inUse }
    }

    // MARK: Decision

    /// Any process running input counts, except Clackwork itself and system listeners.
    /// `isApp` is injectable for tests.
    static func anyRunningInput(_ processes: [Process], ownPID: pid_t,
                                isApp: (pid_t) -> Bool = isRegisteredApp) -> Bool {
        processes.contains { $0.isRunningInput && $0.pid != ownPID && !isSystemListener($0, isApp: isApp) }
    }

    /// Apple background services listen without anyone being on a call: CoreSpeech for
    /// Siri's wake word and Dictation, Live Captions, and so on. They are Apple processes
    /// that are not registered applications. FaceTime, QuickTime and Voice Memos are
    /// applications and count. macOS's own microphone indicator draws the same line.
    static func isSystemListener(_ process: Process, isApp: (pid_t) -> Bool = isRegisteredApp) -> Bool {
        guard let bundleID = process.bundleID, bundleID.hasPrefix("com.apple.") else { return false }
        return !isApp(process.pid)
    }

    static func isRegisteredApp(_ pid: pid_t) -> Bool {
        NSRunningApplication(processIdentifier: pid) != nil
    }

    // MARK: Listeners

    /// The C callback; fires on a CoreAudio thread, so the work hops to the main actor.
    private nonisolated static let listener: AudioObjectPropertyListenerProc = { _, _, _, clientData in
        guard let clientData else { return noErr }
        weak var monitor = Unmanaged<MicrophoneMonitor>.fromOpaque(clientData).takeUnretainedValue()
        DispatchQueue.main.async { MainActor.assumeIsolated { monitor?.refresh() } }
        return noErr
    }

    private nonisolated static func addListener(_ item: Watched, to monitor: MicrophoneMonitor) -> Bool {
        var address = address(item.selector)
        let status = AudioObjectAddPropertyListener(item.object, &address, listener,
                                                    Unmanaged.passUnretained(monitor).toOpaque())
        if status != noErr { NSLog("MicrophoneMonitor: could not watch object \(item.object) (status \(status))") }
        return status == noErr
    }

    private nonisolated static func removeListener(_ item: Watched, from monitor: MicrophoneMonitor) {
        var address = address(item.selector)
        AudioObjectRemovePropertyListener(item.object, &address, listener, Unmanaged.passUnretained(monitor).toOpaque())
    }

    // MARK: HAL queries

    struct Process {
        let object: AudioObjectID
        let pid: pid_t
        let isRunningInput: Bool
        let bundleID: String?

        nonisolated init(object: AudioObjectID = 0, pid: pid_t, isRunningInput: Bool, bundleID: String? = nil) {
            self.object = object
            self.pid = pid
            self.isRunningInput = isRunningInput
            self.bundleID = bundleID
        }
    }

    /// Every process CoreAudio knows about, or nil where the process API doesn't exist.
    /// The pid and bundle ID are read only for processes running input, which is all the
    /// decision needs.
    nonisolated static func processes() -> [Process]? {
        guard let objects: [AudioObjectID] = array(of: systemObject, kAudioHardwarePropertyProcessObjectList) else {
            return nil
        }
        return objects.map { object in
            let running = (value(of: object, kAudioProcessPropertyIsRunningInput) as UInt32?).map { $0 != 0 } ?? false
            return Process(
                object: object,
                pid: running ? (value(of: object, kAudioProcessPropertyPID) ?? -1) : -1,
                isRunningInput: running,
                bundleID: running ? string(of: object, kAudioProcessPropertyBundleID) : nil
            )
        }
    }

    private nonisolated static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private nonisolated static func value<T>(of object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var address = address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr,
              size == UInt32(MemoryLayout<T>.size) else { return nil }
        return pointer.pointee
    }

    private nonisolated static func array<T>(of object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [T]? {
        var address = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr else { return nil }
        let capacity = Int(size) / MemoryLayout<T>.size
        guard capacity > 0 else { return [] }
        let buffer = UnsafeMutablePointer<T>.allocate(capacity: capacity)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, buffer) == noErr else { return nil }
        return Array(UnsafeBufferPointer(start: buffer, count: Int(size) / MemoryLayout<T>.size))
    }

    private nonisolated static func string(of object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var result: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &result) == noErr else { return nil }
        return result?.takeRetainedValue() as String?
    }
}
