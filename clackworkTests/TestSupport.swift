import Foundation

/// Polls until `condition` holds or `timeout` passes, then returns; the caller asserts.
///
/// For work the code under test schedules on a timer or task. A fixed sleep races that
/// work and loses on a busy machine (CI runners, a parallel build); polling with a long
/// deadline passes as soon as the work is done and only waits the full time on failure.
@MainActor
func waitUntil(timeout: Duration = .seconds(3), _ condition: @MainActor () -> Bool) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !condition(), clock.now < deadline {
        try await Task.sleep(for: .milliseconds(20))
    }
}
