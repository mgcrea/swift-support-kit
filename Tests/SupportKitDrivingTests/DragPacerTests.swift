import Foundation
import Testing

@testable import SupportKitDriving

/// When a paced drag sends each event, apart from any window: the end-to-end check is
/// `PointerDeliveryTests`.
@Suite struct DragPacerTests {
  let pacer = DragPacer(steps: 4, durationMs: 100)

  func seconds(_ wait: DragPacer.Wait) -> TimeInterval? {
    if case .after(let seconds) = wait { seconds } else { nil }
  }

  /// Step k of n at k × duration / n, and the up with the last step.
  @Test func theStepsAreSpreadOverTheDuration() {
    #expect(abs(pacer.due(0) - 0.025) < 1e-9)
    #expect(abs(pacer.due(3) - 0.1) < 1e-9)
    #expect(abs(pacer.due(4) - 0.1) < 1e-9)
  }

  @Test func aStepWaitsForItsTime() throws {
    let wait = try #require(
      seconds(pacer.wait(for: 1, at: 0.03, previousTaken: true, previousSent: 0.025)))
    #expect(abs(wait - 0.02) < 1e-9)
  }

  @Test func theFirstStepGoesAtItsTime() {
    #expect(
      pacer.wait(for: 0, at: 0.025, previousTaken: true, previousSent: nil)
        == .now(unconfirmed: false))
  }

  /// Due, but the app has not taken the step before: it looks again shortly, rather than
  /// queueing two steps together.
  @Test func aDueStepWaitsForTheOneBeforeToBeTaken() {
    #expect(
      pacer.wait(for: 2, at: 0.2, previousTaken: false, previousSent: 0.05)
        == .after(DragPacer.poll))
    #expect(
      pacer.wait(for: 2, at: 0.2, previousTaken: true, previousSent: 0.05)
        == .now(unconfirmed: false))
  }

  /// A drag never leaves a button held down: after `patience` the step goes, and is counted.
  @Test func aStepGoesAnywayOncePatienceRunsOut() {
    #expect(
      pacer.wait(for: 4, at: 1.2, previousTaken: false, previousSent: 0.1)
        == .now(unconfirmed: true))
  }

  @Test func aDragOfNoTimeSendsEachStepAtOnce() {
    let instant = DragPacer(steps: 2, durationMs: 0)
    #expect(
      instant.wait(for: 1, at: 0, previousTaken: true, previousSent: 0) == .now(unconfirmed: false))
  }
}
