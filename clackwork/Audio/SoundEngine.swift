import AVFoundation
import Foundation

/// Low-latency playback of keyboard sounds (FR-2, FR-3, FR-4).
///
/// All samples are rendered once at launch and kept in memory. A pool of player
/// nodes lets fast typing overlap sounds without cutting any off. Each press
/// picks a random variation and nudges pitch and level by up to ±3%.
final class SoundEngine {
    static let variationsPerSound = 3

    private let engine = AVAudioEngine()
    private let format: AVAudioFormat
    private var voices: [(player: AVAudioPlayerNode, pitch: AVAudioUnitVarispeed)] = []
    private var nextVoice = 0
    private var buffers: [Key: [AVAudioPCMBuffer]] = [:]
    private var observer: NSObjectProtocol?

    private struct Key: Hashable {
        let profileID: String
        let key: KeyType
    }

    /// The rate all samples are rendered at.
    var sampleRate: Double { format.sampleRate }

    /// Master volume 0...1, independent of the system volume (FR-10).
    var volume: Float = 0.7 {
        didSet { engine.mainMixerNode.outputVolume = volume }
    }

    init(voiceCount: Int = 12) {
        // Render at a fixed rate so quality doesn't depend on whichever output device is
        // active at launch (a headset in call mode can report 24 kHz). Every voice feeds
        // the mixer at this same rate, so the only sample-rate conversion happens once,
        // between the mixer and the output device.
        format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        engine.connect(engine.mainMixerNode, to: engine.outputNode,
                       format: AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        for _ in 0..<voiceCount {
            let player = AVAudioPlayerNode()
            let pitch = AVAudioUnitVarispeed()
            engine.attach(player)
            engine.attach(pitch)
            engine.connect(player, to: pitch, format: format)
            engine.connect(pitch, to: engine.mainMixerNode, format: format)
            voices.append((player, pitch))
        }
        engine.mainMixerNode.outputVolume = volume
        preloadAllSounds()
        start()

        // Recover after output device changes or sleep/wake (reliability requirement).
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.start() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Plays the sound for a key type in the given profile.
    func play(_ key: KeyType, profile: KeyboardProfile) {
        guard let options = buffers[Key(profileID: profile.id, key: key)], !options.isEmpty else { return }
        if !engine.isRunning { start() }
        guard engine.isRunning else { return }

        let buffer = options.randomElement()!
        let voice = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count

        voice.pitch.rate = Float.random(in: 0.97...1.03)
        voice.player.volume = Float.random(in: 0.97...1.0)
        // `.interrupts` replaces whatever the voice was playing; no stop() needed,
        // which keeps the render thread from doing a reset mid-cycle.
        voice.player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !voice.player.isPlaying { voice.player.play() }
    }

    private func start() {
        guard !engine.isRunning else { return }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            NSLog("SoundEngine: could not start audio engine: \(error)")
        }
    }

    private func preloadAllSounds() {
        for profile in KeyboardProfile.all {
            for key in KeyType.allCases {
                var variations: [AVAudioPCMBuffer] = []
                for variation in 0..<Self.variationsPerSound {
                    let samples = SoundSynthesizer.render(
                        profileID: profile.id, key: key, variation: variation, sampleRate: format.sampleRate
                    )
                    if let buffer = makeBuffer(samples) { variations.append(buffer) }
                }
                buffers[Key(profileID: profile.id, key: key)] = variations
            }
        }
    }

    private func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        return buffer
    }

    #if DEBUG
    /// Writes every preloaded sound as a WAV file, for auditioning the placeholders.
    func exportSounds(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (key, variations) in buffers {
            for (index, buffer) in variations.enumerated() {
                let url = directory.appendingPathComponent("\(key.profileID)-\(key.key.rawValue)-\(index + 1).wav")
                let file = try AVAudioFile(forWriting: url, settings: format.settings)
                try file.write(from: buffer)
            }
        }
    }
    #endif
}
