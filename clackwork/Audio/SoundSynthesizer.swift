import Foundation

/// Generates placeholder keyboard sounds in code until real recordings exist.
///
/// Every sound is a sum of three parts shaped by exponential decays:
/// a band-passed noise "click", a low sine "body" (the thock), and an optional
/// ringing "ping" (buckling spring). Each profile has its own recipe, each key
/// type bends it, and each variation adds a small pitch and level offset.
enum SoundSynthesizer {
    struct Recipe {
        var clickLevel: Float
        var clickFrequency: Float
        var clickQ: Float
        var clickDecay: Float          // seconds

        var bodyLevel: Float
        var bodyFrequency: Float
        var bodyDecay: Float
        var bodyAttack: Float          // seconds

        var pingLevel: Float
        var pingFrequency: Float
        var pingDecay: Float

        var secondClickDelay: Float    // seconds, 0 = none
        var secondClickLevel: Float
    }

    static func recipe(for profileID: String) -> Recipe {
        switch profileID {
        case "mx-blue":
            return Recipe(clickLevel: 1.0, clickFrequency: 4200, clickQ: 2.5, clickDecay: 0.007,
                          bodyLevel: 0.25, bodyFrequency: 620, bodyDecay: 0.014, bodyAttack: 0.0005,
                          pingLevel: 0.12, pingFrequency: 5400, pingDecay: 0.018,
                          secondClickDelay: 0.028, secondClickLevel: 0.55)
        case "mx-brown":
            return Recipe(clickLevel: 0.45, clickFrequency: 1900, clickQ: 1.4, clickDecay: 0.010,
                          bodyLevel: 0.55, bodyFrequency: 360, bodyDecay: 0.024, bodyAttack: 0.001,
                          pingLevel: 0, pingFrequency: 0, pingDecay: 0.01,
                          secondClickDelay: 0, secondClickLevel: 0)
        case "lubed-linear":
            return Recipe(clickLevel: 0.22, clickFrequency: 1300, clickQ: 1.0, clickDecay: 0.009,
                          bodyLevel: 1.0, bodyFrequency: 185, bodyDecay: 0.045, bodyAttack: 0.0015,
                          pingLevel: 0, pingFrequency: 0, pingDecay: 0.01,
                          secondClickDelay: 0, secondClickLevel: 0)
        case "model-m":
            return Recipe(clickLevel: 0.9, clickFrequency: 3100, clickQ: 2.0, clickDecay: 0.009,
                          bodyLevel: 0.4, bodyFrequency: 520, bodyDecay: 0.020, bodyAttack: 0.0005,
                          pingLevel: 0.45, pingFrequency: 2650, pingDecay: 0.065,
                          secondClickDelay: 0.012, secondClickLevel: 0.6)
        default: // topre
            return Recipe(clickLevel: 0.28, clickFrequency: 950, clickQ: 1.0, clickDecay: 0.014,
                          bodyLevel: 1.0, bodyFrequency: 255, bodyDecay: 0.060, bodyAttack: 0.003,
                          pingLevel: 0, pingFrequency: 0, pingDecay: 0.01,
                          secondClickDelay: 0, secondClickLevel: 0)
        }
    }

    /// Bends the base recipe for the kind of key that was pressed.
    static func adjust(_ base: Recipe, for key: KeyType) -> Recipe {
        var r = base
        switch key {
        case .standard:
            break
        case .space:
            r.bodyFrequency *= 0.6; r.bodyLevel *= 1.3; r.bodyDecay *= 1.6
            r.clickLevel *= 0.8; r.clickFrequency *= 0.85
        case .returnKey:
            r.bodyFrequency *= 0.75; r.bodyLevel *= 1.15; r.bodyDecay *= 1.3
        case .backspace:
            r.bodyFrequency *= 0.9; r.clickLevel *= 1.1; r.clickFrequency *= 1.05
        case .modifier:
            r.bodyFrequency *= 0.8; r.bodyLevel *= 0.7; r.clickLevel *= 0.7; r.pingLevel *= 0.7
        }
        return r
    }

    /// Renders one mono sample buffer. `variation` seeds the noise and a small pitch/level offset.
    static func render(profileID: String, key: KeyType, variation: Int, sampleRate: Double) -> [Float] {
        var r = adjust(recipe(for: profileID), for: key)
        var rng = SeededGenerator(seed: stableHash("\(profileID)/\(key.rawValue)/\(variation)"))

        let pitch = Float.random(in: 0.96...1.04, using: &rng)
        let level = Float.random(in: 0.88...1.0, using: &rng)
        r.clickFrequency *= pitch; r.bodyFrequency *= pitch; r.pingFrequency *= pitch
        r.clickDecay *= Float.random(in: 0.9...1.1, using: &rng)

        let longest = max(r.clickDecay, r.bodyDecay, r.pingDecay) * 6 + r.secondClickDelay
        let duration = min(max(longest, 0.06), 0.4)
        let count = Int(duration * Float(sampleRate))
        var out = [Float](repeating: 0, count: count)
        let fs = Float(sampleRate)

        // Click: band-passed noise with a fast decay.
        var filter = Biquad.bandpass(frequency: r.clickFrequency, q: r.clickQ, sampleRate: fs)
        for i in 0..<count {
            let t = Float(i) / fs
            let noise = Float.random(in: -1...1, using: &rng)
            var env = exp(-t / r.clickDecay)
            if r.secondClickDelay > 0, t >= r.secondClickDelay {
                env += r.secondClickLevel * exp(-(t - r.secondClickDelay) / r.clickDecay)
            }
            out[i] += r.clickLevel * env * filter.process(noise)
        }

        // Body: low sine with a short attack, slight downward pitch glide.
        if r.bodyLevel > 0 {
            var phase: Float = 0
            for i in 0..<count {
                let t = Float(i) / fs
                let attack = min(t / r.bodyAttack, 1)
                let env = attack * exp(-t / r.bodyDecay)
                let freq = r.bodyFrequency * (1 + 0.15 * exp(-t / 0.004))
                phase += 2 * .pi * freq / fs
                out[i] += r.bodyLevel * env * sin(phase)
            }
        }

        // Ping: metallic ring.
        if r.pingLevel > 0 {
            var phase: Float = 0
            for i in 0..<count {
                let t = Float(i) / fs
                let env = exp(-t / r.pingDecay)
                phase += 2 * .pi * r.pingFrequency / fs
                out[i] += r.pingLevel * env * sin(phase)
            }
        }

        // Normalize to a sane peak, then apply the per-variation level and a soft knee.
        let peak = out.reduce(0) { max($0, abs($1)) }
        let gain = peak > 0 ? 0.8 * level / peak : 0
        for i in 0..<count {
            out[i] = tanh(out[i] * gain * 1.2) / 1.2
        }
        // Fade the tail so there is never a click at the end of the buffer.
        let fade = min(count, Int(0.005 * fs))
        for i in 0..<fade {
            out[count - 1 - i] *= Float(i) / Float(fade)
        }
        return out
    }

    /// RBJ band-pass biquad.
    private struct Biquad {
        var b0: Float, b1: Float, b2: Float, a1: Float, a2: Float
        var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0

        static func bandpass(frequency: Float, q: Float, sampleRate: Float) -> Biquad {
            let w0 = 2 * Float.pi * min(frequency, sampleRate * 0.45) / sampleRate
            let alpha = sin(w0) / (2 * q)
            let a0 = 1 + alpha
            return Biquad(b0: alpha / a0, b1: 0, b2: -alpha / a0, a1: -2 * cos(w0) / a0, a2: (1 - alpha) / a0)
        }

        mutating func process(_ x: Float) -> Float {
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x; y2 = y1; y1 = y
            return y
        }
    }

    /// FNV-1a; `String.hashValue` is randomized per launch and may be negative.
    private static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    /// Deterministic generator so the same variation always sounds the same.
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
        mutating func next() -> UInt64 {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return state
        }
    }
}
