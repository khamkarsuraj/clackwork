import AVFoundation
import Foundation

/// Loads recorded keyboard sounds for a profile from the app bundle.
///
/// A pack is `<profile-id>.caf` plus `<profile-id>.json` in the Sounds folder, in the
/// single-file format: one audio file, and a map from key scan code to a
/// `[start ms, duration ms]` slice of it. Import new packs with `scripts/import_soundpack.sh`.
nonisolated enum SoundPack {
    private struct Config: Decodable {
        let keyDefineType: String
        let defines: [String: [Double]?]

        enum CodingKeys: String, CodingKey {
            case keyDefineType = "key_define_type"
            case defines
        }
    }

    /// Recorded samples for each key type, mono at `sampleRate`, or nil when the profile
    /// has no pack.
    ///
    /// Each slice has its leading silence trimmed, because every millisecond of silence
    /// before the click is a millisecond of latency (issue #32). At most `maxVariations`
    /// distinct slices are kept per key type, spread evenly across the pack.
    static func load(profileID: String, sampleRate: Double, maxVariations: Int,
                     bundle: Bundle = .main) -> [KeyType: [[Float]]]? {
        guard let audioURL = bundle.url(forResource: profileID, withExtension: "caf"),
              let configURL = bundle.url(forResource: profileID, withExtension: "json") else { return nil }
        do {
            let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: configURL))
            guard config.keyDefineType == "single" else {
                NSLog("SoundPack: \(profileID) uses unsupported key_define_type \(config.keyDefineType)")
                return nil
            }
            let audio = try readMono(audioURL, sampleRate: sampleRate)
            return slices(from: audio, config: config, sampleRate: sampleRate, maxVariations: maxVariations)
        } catch {
            NSLog("SoundPack: could not load \(profileID): \(error)")
            return nil
        }
    }

    /// Which key type a pack's key code belongs to. The codes are PC scan codes,
    /// with 0xE0-prefixed keys written as 3584 + code.
    static func keyType(forScanCode code: Int) -> KeyType {
        switch code {
        case 57: return .space
        case 28, 3612: return .returnKey                          // Return, keypad Enter
        case 14, 3667: return .backspace                          // Backspace, Delete
        case 42, 54, 29, 3613, 56, 3640, 3675, 3676, 58: return .modifier // Shift, Ctrl, Alt, Cmd, Caps Lock
        default: return .standard
        }
    }

    /// Peak level every pack is normalized to, so packs play at the same loudness.
    static let targetPeak: Float = 0.8

    // MARK: Private

    private static func readMono(_ url: URL, sampleRate: Double) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            return []
        }
        try file.read(into: buffer)
        guard let channels = buffer.floatChannelData else { return [] }

        let frames = Int(buffer.frameLength)
        let channelCount = Int(format.channelCount)
        var mono = [Float](repeating: 0, count: frames)
        for c in 0..<channelCount {
            let channel = channels[c]
            for i in 0..<frames { mono[i] += channel[i] / Float(channelCount) }
        }
        // Resampling to the engine rate is a "pitch" change by the ratio of the two rates.
        return SoundEngine.resample(mono, pitch: format.sampleRate / sampleRate)
    }

    private static func slices(from audio: [Float], config: Config, sampleRate: Double,
                               maxVariations: Int) -> [KeyType: [[Float]]] {
        // Group distinct slices by key type; many keys share the same slice.
        var byType: [KeyType: [[Double]]] = [:]
        var seen = Set<Double>()
        for (code, slice) in config.defines.sorted(by: { (Int($0.key) ?? 0) < (Int($1.key) ?? 0) }) {
            guard let slice, slice.count == 2, let scanCode = Int(code), seen.insert(slice[0]).inserted else { continue }
            byType[keyType(forScanCode: scanCode), default: []].append(slice)
        }

        var result: [KeyType: [[Float]]] = [:]
        for (type, all) in byType {
            let picked = evenlySpaced(all, count: maxVariations)
            result[type] = picked.compactMap { cut(audio, slice: $0, sampleRate: sampleRate) }
        }
        // Packs without a dedicated sound for a type borrow the standard key.
        for type in KeyType.allCases where result[type]?.isEmpty ?? true {
            result[type] = result[.standard]
        }
        // One gain for the whole pack, so packs match each other while keeping the
        // pack's own balance between keys.
        let peak = result.values.joined().joined().reduce(0) { max($0, abs($1)) }
        if peak > 0 {
            let gain = targetPeak / peak
            for (type, sounds) in result { result[type] = sounds.map { $0.map { $0 * gain } } }
        }
        return result
    }

    private static func evenlySpaced<T>(_ items: [T], count: Int) -> [T] {
        guard items.count > count, count > 0 else { return items }
        return (0..<count).map { items[$0 * items.count / count] }
    }

    private static func cut(_ audio: [Float], slice: [Double], sampleRate: Double) -> [Float]? {
        let start = Int(slice[0] / 1000 * sampleRate)
        let end = min(audio.count, start + Int(slice[1] / 1000 * sampleRate))
        guard start >= 0, start < end else { return nil }
        var samples = Array(audio[start..<end])

        // Trim leading silence: start 1 ms before the first sample above 5% of the peak.
        let peak = samples.reduce(0) { max($0, abs($1)) }
        guard peak > 0 else { return nil }
        if let onset = samples.firstIndex(where: { abs($0) > peak * 0.05 }) {
            let keep = max(0, onset - Int(0.001 * sampleRate))
            samples.removeFirst(keep)
        }
        // Short fades so slices never start or end with a click.
        let fadeIn = min(samples.count, Int(0.0005 * sampleRate))
        for i in 0..<fadeIn { samples[i] *= Float(i) / Float(fadeIn) }
        let fadeOut = min(samples.count, Int(0.005 * sampleRate))
        for i in 0..<fadeOut { samples[samples.count - 1 - i] *= Float(i) / Float(fadeOut) }
        return samples
    }
}
