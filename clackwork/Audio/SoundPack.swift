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
            let file = try AVAudioFile(forReading: audioURL)
            return try slices(config: config, sampleRate: sampleRate, maxVariations: maxVariations) { slice in
                try readMono(slice, from: file, sampleRate: sampleRate)
            }
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

    /// Reads one `[start ms, duration ms]` slice of the pack as mono at `sampleRate`.
    ///
    /// Only the slices in use are decoded. Decoding a whole pack (40-55 s) left a freed
    /// 7-10 MB buffer per profile that malloc kept counted against the app (issue #34).
    ///
    /// The slice is resampled on the pack's own timeline, with the same interpolation as
    /// `SoundEngine.resample`, so it comes out sample for sample as if cut from the whole
    /// resampled pack. Resampling the slice on its own shifts the interpolation by a
    /// fraction of a sample, which moved some silence trims by up to 30 ms.
    private static func readMono(_ slice: [Double], from file: AVAudioFile, sampleRate: Double) throws -> [Float] {
        let format = file.processingFormat
        let length = Int(file.length)
        // Converting to the engine rate is a "pitch" change by the ratio of the two rates.
        let pitch = format.sampleRate / sampleRate
        let resampledLength = length > 1 ? Int(Double(length - 1) / pitch) + 1 : length
        let first = Int(slice[0] / 1000 * sampleRate)
        let end = min(resampledLength, first + Int(slice[1] / 1000 * sampleRate))
        guard first >= 0, first < end else { return [] }

        // The file frames those output samples interpolate between.
        let readStart = Int(Double(first) * pitch)
        let readEnd = min(length, Int(Double(end - 1) * pitch) + 2)
        let count = AVAudioFrameCount(readEnd - readStart)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else { return [] }
        file.framePosition = AVAudioFramePosition(readStart)
        try file.read(into: buffer, frameCount: count)
        guard let channels = buffer.floatChannelData, buffer.frameLength == count else { return [] }

        let frames = Int(buffer.frameLength)
        let channelCount = Int(format.channelCount)
        var mono = [Float](repeating: 0, count: frames)
        for c in 0..<channelCount {
            let channel = channels[c]
            for i in 0..<frames { mono[i] += channel[i] / Float(channelCount) }
        }

        var out = [Float](repeating: 0, count: end - first)
        for i in first..<end {
            let position = Double(i) * pitch
            let index = Int(position)
            let next = min(index + 1, length - 1)
            let fraction = Float(position - Double(index))
            let a = mono[index - readStart], b = mono[next - readStart]
            out[i - first] = a + (b - a) * fraction
        }
        return out
    }

    private static func slices(config: Config, sampleRate: Double, maxVariations: Int,
                               read: ([Double]) throws -> [Float]) rethrows -> [KeyType: [[Float]]] {
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
            result[type] = try picked.compactMap { shape(try read($0), sampleRate: sampleRate) }
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

    private static func shape(_ slice: [Float], sampleRate: Double) -> [Float]? {
        guard !slice.isEmpty else { return nil }
        var samples = slice

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
