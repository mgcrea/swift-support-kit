import SwiftUI

/// The mark beside a control Pro unlocks: a "PRO" capsule, white on the accent colour.
///
/// Contour's mark, the most legible of the three the fleet drew by hand (Cadence's tinted
/// chip faded into a selected row, Filiation's padlock needs a glyph to sit on). And
/// Contour's rule: nothing until the store has answered, since a badge drawn at launch is
/// shown to somebody who has already paid, then the capsule while locked, then nothing.
public struct ProBadge: View {
  private let state: ProPurchaseState

  public init(state: ProPurchaseState) {
    self.state = state
  }

  /// Whether `state` draws the capsule: only `.locked`.
  public nonisolated static func isShown(for state: ProPurchaseState) -> Bool {
    if case .locked = state { return true }
    return false
  }

  /// The title of a menu or picker item, which cannot draw a capsule: "Concert Grand (Pro)"
  /// while locked, the title alone otherwise. Cadence, Contour and Pochette each wrote this
  /// suffix by hand; here it is in the package's catalog, translated once.
  public nonisolated static func title(_ title: String, isLocked: Bool) -> String {
    isLocked ? localized("\(title) (Pro)") : title
  }

  public var body: some View {
    if Self.isShown(for: state) {
      Text(localized("PRO"))
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.accentColor, in: Capsule())
        .accessibilityLabel(Text(localized("Requires Pro")))
    }
  }
}

#Preview("Locked, light and dark") {
  VStack(spacing: 12) {
    HStack { Text(verbatim: "Arcade Effects"); ProBadge(state: .locked(price: "$9.99")) }
    HStack { Text(verbatim: "Arcade Effects"); ProBadge(state: .unlocked) }
  }
  .padding()
}
