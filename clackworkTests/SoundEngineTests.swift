import Testing
@testable import clackwork

/// FR-3: each press varies in pitch within ±3%.
struct SoundEngineTests {
    @Test func pitchStepsStayWithinThreePercent() {
        #expect(SoundEngine.pitchSteps.contains(1.0))
        for step in SoundEngine.pitchSteps { #expect((0.97...1.03).contains(step)) }
    }

    @Test func naturalPitchLeavesSamplesUnchanged() {
        let samples: [Float] = [0, 0.5, 1, 0.5, 0]
        #expect(SoundEngine.resample(samples, pitch: 1) == samples)
    }

    @Test func higherPitchShortensAndKeepsTheStart() {
        let samples = (0..<1_000).map { Float($0) / 1_000 }
        let shifted = SoundEngine.resample(samples, pitch: 1.03)
        #expect(shifted.count == Int(Double(samples.count - 1) / 1.03) + 1)
        #expect(shifted.first == samples.first)
        #expect(shifted.allSatisfy { (0...1).contains($0) })
    }

    @Test func lowerPitchLengthens() {
        let samples = [Float](repeating: 0.25, count: 1_000)
        #expect(SoundEngine.resample(samples, pitch: 0.97).count > samples.count)
    }
}
