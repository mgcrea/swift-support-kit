import Foundation
import Testing

@testable import SupportKitDriving

/// When a paced drag sends each event, apart from any window: the end-to-end check is
/// `PointerDeliveryTests`.
@Suite struct DragPacerTests {
  /// Four steps over 100 ms.
  func pacer() -> DragPacer { DragPacer(steps: 4, durationMs: 100) }

  func seconds(_ wait: DragPacer.Wait) -> TimeInterval? {
    if case .after(let seconds) = wait { seconds } else { nil }
  }

  /// Step k of n at k × duration / n, and the up with the last step.
  @Test func theStepsAreSpreadOverTheDuration() {
    let pacer = pacer()
    #expect(abs(pacer.due(0) - 0.025) < 1e-9)
    #expect(abs(pacer.due(3) - 0.1) < 1e-9)
    #expect(abs(pacer.due(4) - 0.1) < 1e-9)
  }

  @Test func aStepWaitsForItsTime() throws {
    var pacer = pacer()
    let wait = try #require(
      seconds(pacer.wait(for: 1, at: 0.03, previousTaken: true, previousSent: 0.025)))
    #expect(abs(wait - 0.02) < 1e-9)
  }

  @Test func theFirstStepGoesAtItsTime() {
    var pacer = pacer()
    #expect(
      pacer.wait(for: 0, at: 0.025, previousTaken: true, previousSent: nil)
        == .now(unconfirmed: false))
  }

  /// Due, but the app has not taken the step before: it looks again shortly, rather than
  /// queueing two steps together.
  @Test func aDueStepWaitsForTheOneBeforeToBeTaken() {
    var pacer = pacer()
    #expect(
      pacer.wait(for: 2, at: 0.2, previousTaken: false, previousSent: 0.05)
        == .after(DragPacer.poll))
    #expect(
      pacer.wait(for: 2, at: 0.2, previousTaken: true, previousSent: 0.05)
        == .now(unconfirmed: false))
    #expect(pacer.unconfirmed == 0)
  }

  /// A drag never leaves a button held down: after `patience` the step goes, and is counted.
  @Test func aStepGoesAnywayOncePatienceRunsOut() {
    var pacer = pacer()
    #expect(
      pacer.wait(for: 4, at: 1.2, previousTaken: false, previousSent: 0.1)
        == .now(unconfirmed: true))
    #expect(pacer.unconfirmed == 1)
  }

  /// Patience is spent once per drag: after one event went unconfirmed, the rest go at their
  /// own times without waiting, so an app that takes nothing holds the drag up for
  /// `patience` at most, not once per step.
  @Test func patienceIsABoundPerDrag() throws {
    var pacer = DragPacer(steps: 16, durationMs: 400)
    #expect(
      pacer.wait(for: 1, at: 0.05, previousTaken: false, previousSent: 0.025)
        == .after(DragPacer.poll))
    #expect(
      pacer.wait(for: 1, at: 1.03, previousTaken: false, previousSent: 0.025)
        == .now(unconfirmed: true))
    for index in 2...16 {
      // Never taken, each looked at once it is due and the one before has gone.
      #expect(
        pacer.wait(for: index, at: 1.03, previousTaken: false, previousSent: 1.03)
          == .now(unconfirmed: true))
    }
    #expect(pacer.unconfirmed == 16)

    // Still at its own time: an unconfirmed drag is not sent all at once.
    var early = DragPacer(steps: 16, durationMs: 400)
    _ = early.wait(for: 0, at: 1.03, previousTaken: true, previousSent: nil)
    _ = early.wait(for: 1, at: 1.03, previousTaken: false, previousSent: 0.025)
    let wait = try #require(
      seconds(early.wait(for: 2, at: 0.05, previousTaken: false, previousSent: 0.04)))
    #expect(abs(wait - 0.025) < 1e-9)
  }

  @Test func aDragOfNoTimeSendsEachStepAtOnce() {
    var instant = DragPacer(steps: 2, durationMs: 0)
    #expect(
      instant.wait(for: 1, at: 0, previousTaken: true, previousSent: 0) == .now(unconfirmed: false))
  }
}
