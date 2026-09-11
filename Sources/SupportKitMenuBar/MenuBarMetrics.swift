#if os(macOS)
  import AppKit
  import SwiftUI

  /// The panel's fixed dimensions.
  ///
  /// These were five sets of inline literals across five apps, restated in prose
  /// more often than in code — bastion's own comments disagreed about its width
  /// (340 in one, 320 in another, `320` in the `frame`), and cupertino wrote
  /// `320` into four comments and one `frame`. Every one of those sentences was
  /// justifying a measurement, so a change to the number silently invalidated
  /// the reasoning that argued for it. Here the number and the reasoning are in
  /// the same place.
  public struct MenuBarMetrics: Sendable {
    public let width: CGFloat
    public let padding: CGFloat
    public let spacing: CGFloat

    public init(width: CGFloat, padding: CGFloat, spacing: CGFloat) {
      self.width = width
      self.padding = padding
      self.spacing = spacing
    }

    /// 320 / 14 / 12 — what the fleet converged on without coordinating.
    ///
    /// Four of the five panels were already 320. The fifth (armada) was 280 and
    /// was the one at real risk of truncating its own footer: the siblings had
    /// measured a fourth *text* button truncating "Open Cupertino" at 320, and
    /// armada was carrying "Open Armada" plus two more controls in forty points
    /// less. Widening it is the cheaper half of that fix.
    ///
    /// 14 and 12 are bastion's and cupertino's, which are the two densest panels
    /// and the two that were tuned most. The other three move by two points.
    public static let `default` = MenuBarMetrics(width: 320, padding: 14, spacing: 12)

    /// The tallest the scrolling body may grow before it starts scrolling.
    ///
    /// Derived from the screen rather than fixed, because the right answer is
    /// not the same on a laptop and a studio display — and a constant tuned on
    /// one is wrong on the other in the direction nobody notices until a panel
    /// is cut off.
    ///
    /// ⚠️ Read at layout time and **not** reactive to a display change. A panel
    /// rebuilt on every open (which `MenuBarExtra` guarantees — its content is
    /// lazy) re-reads this each time, so the window it could be wrong in is a
    /// display change *while the panel is open*. That is not worth a screen
    /// observer.
    ///
    /// `NSScreen.main` is the screen holding the key window, which for a panel
    /// that cannot become key may be nil; `screens.first` is the fallback rather
    /// than a magic number.
    public var bodyCap: CGFloat {
      let screen = NSScreen.main ?? NSScreen.screens.first
      guard let visible = screen?.visibleFrame.height else { return 480 }
      // What the body does not get: the header, the footer, their paddings, and
      // a margin so the panel never runs to the bottom edge of the screen.
      let chrome: CGFloat = 160
      // The floor matters more than the ceiling. A very short screen (or a
      // display disconnected mid-session, which reports oddly) must not produce
      // a body of ten points, which reads as a broken panel rather than a small
      // one.
      return max(240, visible - chrome)
    }
  }
#endif
