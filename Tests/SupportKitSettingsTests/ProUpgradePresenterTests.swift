import SwiftUI
import Testing

@testable import SupportKitSettings

private struct Request: Identifiable, Equatable {
  let id: Int
}

@Suite("Pro upgrade presenter")
struct ProUpgradePresenterTests {
  private typealias Presenter = ProUpgradePresenter<Request, EmptyView>

  @Test("A sheet closed after unlocking finishes what was asked")
  func finishesOnceUnlocked() {
    #expect(Presenter.unlocked(Request(id: 1), isUnlocked: true) == Request(id: 1))
  }

  @Test("Not Now, or a failed purchase, finishes nothing")
  func nothingWhileLocked() {
    #expect(Presenter.unlocked(Request(id: 1), isUnlocked: false) == nil)
    #expect(Presenter.unlocked(nil, isUnlocked: true) == nil)
  }
}
