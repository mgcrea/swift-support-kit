import Testing

@testable import SupportKitSettings

@Suite("Pro upgrade sheet")
struct ProUpgradeSheetTests {
  @Test("Unlock carries the price once the store has one")
  func buyWithAPrice() {
    #expect(ProUpgradeSheet.action(state: .locked(price: "$9.99"), isWorking: false)
      == .buy(price: "$9.99"))
  }

  @Test("No product: Unavailable, not an Unlock that fails")
  func unavailableWithoutAPrice() {
    #expect(ProUpgradeSheet.action(state: .locked(price: nil), isWorking: false) == .unavailable)
  }

  @Test("A purchase or restore in flight, or a store not yet answered, shows progress")
  func workingWhileBusyOrUnknown() {
    #expect(ProUpgradeSheet.action(state: .locked(price: "$9.99"), isWorking: true) == .working)
    #expect(ProUpgradeSheet.action(state: .unknown, isWorking: false) == .working)
  }

  @Test("Owned: nothing to buy")
  func ownedOnceUnlocked() {
    #expect(ProUpgradeSheet.action(state: .unlocked, isWorking: false) == .owned)
  }
}
