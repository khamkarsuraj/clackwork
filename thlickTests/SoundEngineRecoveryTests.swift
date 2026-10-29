import Testing
@testable import thlick

/// Reliability requirement (issue #41): sound keeps working after the audio engine is
/// stopped and restarted, as happens when the output device changes or the Mac wakes.
///
/// Needs a real output device, so these tests pass trivially where the engine cannot start.
/// Nothing is audible: the engine's mixer is silenced while the tone is measured.
struct SoundEngineRecoveryTests {
    @Test func voicesRenderAgainAfterTheEngineRestarts() {
        let engine = SoundEngine(voiceCount: 2)
        guard engine.isReadyToPlay else { return }
        #expect(engine.renderedPeakOfTestTone() > 0)

        engine.simulateConfigurationChange()

        #expect(engine.isReadyToPlay)
        // Both voices: the bug left every voice in the pool dead, not only the first.
        #expect(engine.renderedPeakOfTestTone() > 0)
        #expect(engine.renderedPeakOfTestTone() > 0)
    }

    @Test func recoversFromRepeatedRestarts() {
        let engine = SoundEngine(voiceCount: 2)
        guard engine.isReadyToPlay else { return }
        for _ in 0..<3 {
            engine.simulateConfigurationChange()
            #expect(engine.renderedPeakOfTestTone() > 0)
        }
    }
}
