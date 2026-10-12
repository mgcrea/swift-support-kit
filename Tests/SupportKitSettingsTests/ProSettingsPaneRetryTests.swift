import SwiftUI
import Testing

@testable import SupportKitSettings

@Suite("Pro pane: Try Again")
struct ProSettingsPaneRetryTests {
  @Test("Try Again when the product did not load and the app can ask again")
  func tryAgainWithRetry() {
    #expect(ProSettingsPane<EmptyView>.showsTryAgain(state: .locked(price: nil), hasRetry: true))
  }

  @Test("The old Unavailable without a retry")
  func unavailableWithoutRetry() {
    #expect(!ProSettingsPane<EmptyView>.showsTryAgain(state: .locked(price: nil), hasRetry: false))
  }

  @Test("Never with a price, unknown or unlocked")
  func neverOtherwise() {
    for state in [ProPurchaseState.locked(price: "$9.99"), .unknown, .unlocked] {
      #expect(!ProSettingsPane<EmptyView>.showsTryAgain(state: state, hasRetry: true))
    }
  }

  /// Asking again for the product is not a purchase or a restore: it must not take Restore
  /// away, so it has its own parameter rather than riding on `isWorking`.
  @Test("Asking again shows progress at the action and leaves Restore alone")
  func loadingProductIsNotWorking() {
    #expect(
      ProSettingsPane<EmptyView>.actionShowsProgress(isWorking: false, isLoadingProduct: true))
    #expect(!ProSettingsPane<EmptyView>.restoreIsDisabled(isWorking: false))
    #expect(
      ProUpgradeSheet.action(
        state: .locked(price: nil), isWorking: false, isLoadingProduct: true, canRetry: true)
        == .working)
  }
}
