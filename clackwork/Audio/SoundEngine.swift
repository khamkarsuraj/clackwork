import AudioToolbox
import AVFoundation
import Foundation
import os

/// Low-latency playback of keyboard sounds (FR-2, FR-3, FR-4).
///
/// Every profile plays a recorded pack from the Sounds folder (see `SoundPack`). All
/// samples are prepared once at launch and kept in memory. A pool of player
/// nodes lets fast typing overlap sounds without cutting any off. Each press
/// picks a random variation, a random pre-rendered pitch step within ±3%, and a
/// random level within -3%.
///
/// Pitch is pre-rendered rather than shifted live: a live pitch unit per voice kept
/// processing silence and roughly doubled idle CPU (see issue #32).
///
/// `play` is safe to call from any thread. The key listener calls it on its own thread so
/// a busy main thread can't delay a key; the UI calls it from the main thread.
nonisolated final class SoundEngine: @unchecked Sendable {
    /// Pitch steps rendered for every sample (FR-3: within ±3%).
    static let pitchSteps: [Double] = [0.97, 0.985, 1.0, 1.015, 1.03]

    /// Target duration of one IO cycle. Keeps the render wait short on every device
    /// (256 frames at 48 kHz, 512 at 96 kHz) without paying for tiny buffers.
    static let targetIOCycle: TimeInterval = 256.0 / 48_000

    private let engine = AVAudioEngine()
    private let format: AVAudioFormat
    private var voices: [AVAudioPlayerNode] = []
    /// Written only during init; read-only afterwards, so safe to read from any thread.
    private var buffers: [Key: [AVAudioPCMBuffer]] = [:]
    /// Guards voice rotation and scheduling, which can happen on two threads at once.
    private let voiceLock = OSAllocatedUnfairLock(initialState: 0)
    private var observer: NSObjectProtocol?

    private struct Key: Hashable {
        let profileID: String
        let key: KeyType
    }

    /// The rate all samples are rendered at.
    var sampleRate: Double { format.sampleRate }

    /// IO buffer size forced with the launch argument `-ioBufferFrames N`, for comparing sizes.
    /// 0 means size the buffer from `targetIOCycle`.
    private let bufferFramesOverride: UInt32

    /// Frames per IO cycle actually in use on the output device.
    var ioBufferFrames: UInt32 {
        guard let unit = engine.outputNode.audioUnit else { return 0 }
        var frames: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioUnitGetProperty(unit, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0, &frames, &size)
        return frames
    }

    /// The output device's own sample rate.
    var outputDeviceSampleRate: Double { engine.outputNode.outputFormat(forBus: 0).sampleRate }

    /// Output device latency (hardware + safety offset), in seconds.
    var outputLatency: TimeInterval { engine.outputNode.presentationLatency }

    /// Worst case from scheduling a sound to it reaching the speaker: one full IO cycle of
    /// waiting plus the output latency. Cached, because it changes only with the device.
    var audioPathLatencyMs: Double { audioPathLatency.withLock { $0 } }
    private let audioPathLatency = OSAllocatedUnfairLock(initialState: 0.0)

    private func updateAudioPathLatency() {
        let deviceRate = outputDeviceSampleRate
        let cycle = deviceRate > 0 ? Double(ioBufferFrames) / deviceRate : 0
        let ms = (cycle + outputLatency) * 1000
        audioPathLatency.withLock { $0 = ms }
    }

    private func applyPreferredBufferSize() {
        guard let unit = engine.outputNode.audioUnit else { return }
        let deviceRate = outputDeviceSampleRate
        guard bufferFramesOverride > 0 || deviceRate > 0 else { return }
        var frames = bufferFramesOverride > 0
            ? bufferFramesOverride
            : UInt32((deviceRate * Self.targetIOCycle).rounded())
        let status = AudioUnitSetProperty(unit, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0,
                                          &frames, UInt32(MemoryLayout<UInt32>.size))
        if status != noErr { NSLog("SoundEngine: could not set IO buffer to \(frames) frames (status \(status))") }
    }

    /// Master volume 0...1, independent of the system volume (FR-10).
    var volume: Float = 0.7 {
        didSet { engine.mainMixerNode.outputVolume = volume }
    }

    init(voiceCount: Int = 12) {
        let override = UserDefaults.standard.integer(forKey: "ioBufferFrames")
        bufferFramesOverride = override > 0 ? UInt32(override) : 0
        // Render at a fixed rate so quality doesn't depend on whichever output device is
        // active at launch (a headset in call mode can report 24 kHz). Every voice feeds
        // the mixer at this same rate, so the only sample-rate conversion happens once,
        // between the mixer and the output device.
        format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        engine.connect(engine.mainMixerNode, to: engine.outputNode,
                       format: AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        for _ in 0..<voiceCount {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            voices.append(player)
        }
        engine.mainMixerNode.outputVolume = volume
        preloadAllSounds()
        start()

        // Recover after output device changes or sleep/wake (reliability requirement).
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            self?.start()
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Plays the sound for a key type in the given profile.
    func play(_ key: KeyType, profile: KeyboardProfile) {
        play(key, profileID: profile.id)
    }

    /// Plays the sound for a key type. Safe to call from any thread.
    func play(_ key: KeyType, profileID: String) {
        guard let options = buffers[Key(profileID: profileID, key: key)], !options.isEmpty else { return }
        guard engine.isRunning else {
            // Restarting the engine belongs on the main thread; this key is skipped.
            DispatchQueue.main.async { [weak self] in self?.start() }
            return
        }
        let buffer = options.randomElement()!
        voiceLock.withLock { next in
            let voice = voices[next]
            next = (next + 1) % voices.count
            voice.volume = Float.random(in: 0.97...1.0)
            // `.interrupts` replaces whatever the voice was playing; no stop() needed,
            // which keeps the render thread from doing a reset mid-cycle.
            voice.scheduleBuffer(buffer, at: nil, options: .interrupts)
            if !voice.isPlaying { voice.play() }
        }
    }

    private func start() {
        guard !engine.isRunning else { return }
        applyPreferredBufferSize()
        engine.prepare()
        do {
            try engine.start()
        } catch {
            NSLog("SoundEngine: could not start audio engine: \(error)")
        }
        updateAudioPathLatency()
    }

    /// Most distinct recorded slices kept per key type; each gets every pitch step.
    static let maxRecordedVariations = 8

    /// Profiles whose pack loaded. A profile missing from here makes no sound.
    private(set) var loadedProfileIDs: Set<String> = []

    private func preloadAllSounds() {
        for profile in KeyboardProfile.all {
            guard let recorded = SoundPack.load(profileID: profile.id, sampleRate: format.sampleRate,
                                                maxVariations: Self.maxRecordedVariations) else {
                NSLog("SoundEngine: no sound pack for \(profile.id); it will be silent")
                continue
            }
            loadedProfileIDs.insert(profile.id)

            for key in KeyType.allCases {
                let sources = recorded[key] ?? []
                var variations: [AVAudioPCMBuffer] = []
                for samples in sources {
                    for step in Self.pitchSteps {
                        if let buffer = makeBuffer(Self.resample(samples, pitch: step)) {
                            variations.append(buffer)
                        }
                    }
                }
                buffers[Key(profileID: profile.id, key: key)] = variations
            }
        }
    }

    /// Distinct sounds (before pitch steps) loaded for a profile and key type.
    func variationCount(profileID: String, key: KeyType) -> Int {
        (buffers[Key(profileID: profileID, key: key)]?.count ?? 0) / Self.pitchSteps.count
    }

    /// Shifts pitch by playing the samples faster (pitch > 1) or slower, with linear
    /// interpolation. Good enough for a few percent; also works for recorded samples.
    static func resample(_ samples: [Float], pitch: Double) -> [Float] {
        guard pitch != 1, samples.count > 1 else { return samples }
        let count = Int(Double(samples.count - 1) / pitch) + 1
        var out = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let position = Double(i) * pitch
            let index = Int(position)
            let next = min(index + 1, samples.count - 1)
            let fraction = Float(position - Double(index))
            out[i] = samples[index] + (samples[next] - samples[index]) * fraction
        }
        return out
    }

    private func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        return buffer
    }

    #if DEBUG
    /// Writes every loaded sound at its natural pitch as a WAV file, for auditioning.
    func exportSounds(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let middle = Self.pitchSteps.firstIndex(of: 1.0) ?? 0
        for (key, all) in buffers {
            let variations = stride(from: middle, to: all.count, by: Self.pitchSteps.count).map { all[$0] }
            for (index, buffer) in variations.enumerated() {
                let url = directory.appendingPathComponent("\(key.profileID)-\(key.key.rawValue)-\(index + 1).wav")
                let file = try AVAudioFile(forWriting: url, settings: format.settings)
                try file.write(from: buffer)
            }
        }
    }
    #endif
}
