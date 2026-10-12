import SupportKit
import Testing

@Suite("Pro purchase state")
struct ProPurchaseStateTests {
  /// The store produces this value without SwiftUI, so it lives in the Foundation-only module.
  @Test("Lives in SupportKit")
  func livesInSupportKit() {
    let state: SupportKit.ProPurchaseState = .locked(price: nil)
    #expect(state == .locked(price: nil))
    #expect(state != .unknown)
  }
}
