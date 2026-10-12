import SupportKitSettings
import Testing

/// Apps name `ProPurchaseState` after `import SupportKitSettings` alone. Moving the enum must
/// not make every one of them add an import, so this file deliberately imports nothing else.
@Suite("Pro purchase state stays visible")
struct ProPurchaseStateVisibilityTests {
  @Test("Nameable with only SupportKitSettings imported")
  func nameableFromSettings() {
    let state: ProPurchaseState = .unlocked
    #expect(ProBadge.isShown(for: state) == false)
  }
}
