import Testing

@testable import SupportKitSettings

@Suite("Pro badge")
struct ProBadgeTests {
  @Test("Drawn while locked, and only then")
  func shownOnlyWhileLocked() {
    #expect(ProBadge.isShown(for: .locked(price: "$9.99")))
    #expect(ProBadge.isShown(for: .locked(price: nil)))
    // Before StoreKit answers, a badge would be shown to somebody who has paid.
    #expect(!ProBadge.isShown(for: .unknown))
    #expect(!ProBadge.isShown(for: .unlocked))
  }

  @Test("A menu item's title says Pro while locked")
  func menuTitle() {
    #expect(ProBadge.title("Concert Grand", isLocked: true) == "Concert Grand (Pro)")
    #expect(ProBadge.title("Concert Grand", isLocked: false) == "Concert Grand")
  }
}
