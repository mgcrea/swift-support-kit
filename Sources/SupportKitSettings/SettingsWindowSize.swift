import SwiftUI

extension View {
  /// Size the settings window, by sizing its **content**.
  ///
  /// Applied to the content, never to the scene and never to the `NSWindow`. A
  /// `Settings` scene sizes itself to what it contains, so
  /// `NSWindow.setContentSize` loses to SwiftUI's clamp — it takes the height
  /// and silently drops the width. The result is a correctly-tall,
  /// wrongly-narrow window, which reads exactly like a screenshot pinner that
  /// ran and mis-measured rather than like a frame applied in the wrong place.
  ///
  /// Three apps in the fleet found this separately and wrote three
  /// near-identical comments about it before anyone noticed it was one bug.
  /// This modifier exists so it is written down once.
  ///
  /// A no-op off macOS: a sheet or a pushed screen takes the size of what is
  /// presenting it, and a hard frame there produces a screen that does not fit
  /// a phone.
  public func settingsWindowSize(_ size: CGSize) -> some View {
    #if os(macOS)
      frame(width: size.width, height: size.height)
    #else
      self
    #endif
  }

  /// The resizable variant, for a window that should have a floor but no ceiling.
  ///
  /// Same rule, same reason: this lands on the content.
  public func settingsWindowSize(
    minWidth: CGFloat,
    idealWidth: CGFloat? = nil,
    minHeight: CGFloat,
    idealHeight: CGFloat? = nil
  ) -> some View {
    #if os(macOS)
      frame(
        minWidth: minWidth,
        idealWidth: idealWidth,
        minHeight: minHeight,
        idealHeight: idealHeight
      )
    #else
      self
    #endif
  }
}

/// How wide the sidebar may be.
public struct SettingsSidebarMetrics: Sendable {
  public let minWidth: CGFloat
  public let idealWidth: CGFloat
  public let maxWidth: CGFloat

  public init(minWidth: CGFloat, idealWidth: CGFloat, maxWidth: CGFloat) {
    self.minWidth = minWidth
    self.idealWidth = idealWidth
    self.maxWidth = maxWidth
  }

  /// 172 / 192 / 240 — the widest of the figures already in the fleet.
  ///
  /// The widest rather than the average, because the cost is asymmetric: a
  /// sidebar with room to spare looks unremarkable, and one forty points too
  /// narrow truncates a pane name in French, which is where the longest labels
  /// are and where nobody looks.
  public static let `default` = SettingsSidebarMetrics(
    minWidth: 172, idealWidth: 192, maxWidth: 240)
}
