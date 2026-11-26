import Foundation
import Testing

@testable import SupportKitSidebar

/// Which section, or row, lights up while something is dragged over a sidebar. Gathered from
/// Cadence's, Valise's and Carbone's suites when their copies moved here.
@Suite("Drop targeting")
struct DropTargetingTests {
  let clients = "clients"
  let podcast = "podcast"
  let ungrouped = "ungrouped"

  @Test func nothingIsLitUntilTheDragIsOverATarget() {
    var targeting = DropTargeting(source: ungrouped)
    #expect(targeting.lit == nil)
    targeting.target(clients, isTargeted: true)
    #expect(targeting.lit == clients)
    targeting.target(clients, isTargeted: false)
    #expect(targeting.lit == nil)
  }

  /// Moving from one row to the next can be heard as entering the next before leaving the
  /// last. The section must not go dark in between.
  @Test func movingBetweenRowsOfOneSectionKeepsItLit() {
    var targeting = DropTargeting(source: ungrouped)
    targeting.target(clients, isTargeted: true)
    targeting.target(clients, isTargeted: true)
    targeting.target(clients, isTargeted: false)
    #expect(targeting.lit == clients)
  }

  @Test func crossingIntoAnotherTargetLightsTheNewOne() {
    var targeting = DropTargeting(source: ungrouped)
    targeting.target(clients, isTargeted: true)
    // Entered before the last row of Clients says it was left.
    targeting.target(podcast, isTargeted: true)
    #expect(targeting.lit == podcast)
    targeting.target(clients, isTargeted: false)
    #expect(targeting.lit == podcast)
  }

  /// Late news that the drag left the target it is now over must not darken it, and leaving
  /// the newer one falls back to the one still held.
  @Test func leavingTheNewerTargetFallsBackToTheOneStillUnderTheDrag() {
    var targeting = DropTargeting(source: ungrouped)
    targeting.target(clients, isTargeted: true)
    targeting.target(podcast, isTargeted: true)
    targeting.target(podcast, isTargeted: false)
    #expect(targeting.lit == clients)
  }

  /// A drop on the row's own section does nothing, so it never lights.
  @Test func theSectionTheDragStartedInNeverLights() {
    var targeting = DropTargeting(source: clients)
    targeting.target(clients, isTargeted: true)
    #expect(targeting.lit == nil)
    targeting.target(podcast, isTargeted: true)
    targeting.target(podcast, isTargeted: false)
    #expect(targeting.lit == nil)
  }

  /// An exit with no matching entry (a drag that began over a target) must not leave a
  /// negative count that keeps a target dark on the next pass.
  @Test func anUnmatchedExitIsForgotten() {
    var targeting = DropTargeting(source: ungrouped)
    targeting.target(clients, isTargeted: false)
    targeting.target(clients, isTargeted: true)
    #expect(targeting.lit == clients)
  }

  /// With no source (a list dragged onto sidebar rows, as in Carbone), every target can light.
  @Test func withNoSourceEveryTargetCanLight() {
    var targeting = DropTargeting<Int>()
    #expect(targeting.lit == nil)
    targeting.target(1, isTargeted: false)
    targeting.target(2, isTargeted: true)
    #expect(targeting.lit == 2)
    targeting.target(2, isTargeted: false)
    #expect(targeting.lit == nil)
  }
}

@MainActor
@Suite("Drop highlight")
struct DropHighlightTests {
  let clients = "clients"
  let podcast = "podcast"
  let ungrouped = "ungrouped"

  @Test func aNewDragForgetsTheLastOne() {
    let highlight = DropHighlight<String>(buttonIsDown: { true })
    highlight.dragBegan(in: clients)
    highlight.target(podcast, isTargeted: true)
    #expect(highlight.lit == podcast)

    highlight.dragEnded()
    #expect(highlight.lit == nil)

    highlight.dragBegan(in: podcast)
    highlight.target(podcast, isTargeted: true)
    #expect(highlight.lit == nil)
  }

  /// The Mac sidebar hears a drag leave a row before it enters the next one of the same
  /// section; the section must not blink dark in between.
  @Test func leavingARowDarkensOnlyIfNoOtherIsEnteredSoon() async throws {
    let highlight = DropHighlight<String>(buttonIsDown: { true })
    highlight.dragBegan(in: ungrouped)
    highlight.target(clients, isTargeted: true)
    highlight.target(clients, isTargeted: false)
    #expect(highlight.lit == clients)
    highlight.target(clients, isTargeted: true)
    try await Task.sleep(for: .milliseconds(200))
    #expect(highlight.lit == clients)

    highlight.target(clients, isTargeted: false)
    #expect(await eventually { highlight.lit == nil })
  }

  /// Between rows with no source and no button to watch, as on iOS: still lit a moment, then
  /// the next row, then dark.
  @Test func withNoButtonToWatchItStillWaitsBeforeGoingDark() async {
    let highlight = DropHighlight<Int>(buttonIsDown: nil)
    highlight.target(1, isTargeted: true)
    highlight.target(1, isTargeted: false)
    #expect(highlight.lit == 1)
    highlight.target(2, isTargeted: true)
    #expect(highlight.lit == 2)
    highlight.target(2, isTargeted: false)
    #expect(highlight.lit == 2)
    #expect(await eventually { highlight.lit == nil })
  }

  /// Let go outside every target, the Mac may never hear the drag leave the last one; the
  /// button coming up ends it anyway.
  @Test func lettingGoOfTheButtonEndsTheDrag() async throws {
    nonisolated(unsafe) var isDown = true
    let highlight = DropHighlight<String>(buttonIsDown: { isDown })
    highlight.dragBegan(in: ungrouped)
    highlight.target(clients, isTargeted: true)
    try await Task.sleep(for: .milliseconds(300))
    #expect(highlight.lit == clients)

    isDown = false
    #expect(await eventually { highlight.lit == nil })
  }

  @Test func aDropDarkensAtOnce() {
    let highlight = DropHighlight<String>(buttonIsDown: { true })
    highlight.dragBegan(in: ungrouped)
    highlight.target(clients, isTargeted: true)
    highlight.dragEnded()
    #expect(highlight.lit == nil)
  }

  /// The drag reports its phase over and over; only a new source resets.
  @Test func repeatingTheSameSourceKeepsWhatIsLit() {
    let highlight = DropHighlight<String>(buttonIsDown: { true })
    highlight.dragBegan(in: clients)
    highlight.target(podcast, isTargeted: true)
    highlight.dragBegan(in: clients)
    #expect(highlight.lit == podcast)
  }

  /// Waits for what a delayed task does, without betting on how late a loaded test run lets
  /// it happen.
  private func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<100 {
      if condition() { return true }
      try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
  }
}
