import CoreGraphics
import Testing

@testable import SupportKitDriving

/// Which of the app's own windows a point lands on. The app hit-tests its own
/// windows, front to back, rather than asking the window server what is on
/// top: a window covered by another app's still takes the click, which is the
/// point of driving it in the background.
@Suite struct WindowPickTests {
  let back = (number: 1, frame: CGRect(x: 0, y: 0, width: 400, height: 300))
  let front = (number: 2, frame: CGRect(x: 100, y: 100, width: 200, height: 100))

  @Test func theFrontWindowWinsWhereTheyOverlap() {
    #expect(WindowPick.window(at: CGPoint(x: 150, y: 150), in: [front, back]) == 2)
  }

  @Test func aWindowBehindTakesThePointsTheFrontOneDoesNotCover() {
    #expect(WindowPick.window(at: CGPoint(x: 10, y: 10), in: [front, back]) == 1)
  }

  @Test func aPointOutsideEveryWindowIsNone() {
    #expect(WindowPick.window(at: CGPoint(x: 500, y: 500), in: [front, back]) == nil)
  }

  /// `CGRect.contains` leaves out the max edges; a click on a window's last
  /// row of pixels is still on it.
  @Test func anEdgeIsInside() {
    #expect(WindowPick.window(at: CGPoint(x: 400, y: 300), in: [back]) == 1)
  }

  /// Top-left global points, as Cupertino sends them, into AppKit's bottom-left
  /// screen space, measured from the primary display's height.
  @Test func flipsATopLeftPointIntoCocoa() {
    #expect(
      WindowPick.cocoa(CGPoint(x: 10, y: 20), primaryHeight: 1000) == CGPoint(x: 10, y: 980))
  }
}
