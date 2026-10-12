import Testing

@testable import SupportKitStore

@Suite("Store client")
struct StoreClientTests {
  @Test("A verified, unrevoked transaction for one of the ids entitles")
  func entitledByAnyListedProduct() async {
    let script = StoreScript()
    await script.setEntitlements([script.transaction("old")])
    #expect(await script.client.isEntitled(to: ["pro", "old"]))
    #expect(await !script.client.isEntitled(to: ["pro"]))
  }

  @Test("A revoked transaction does not entitle")
  func revokedDoesNotEntitle() async {
    let script = StoreScript()
    await script.setEntitlements([script.transaction("pro", revoked: true)])
    #expect(await !script.client.isEntitled(to: ["pro"]))
  }

  @Test("Only the live client is live")
  func onlyLiveIsLive() {
    #expect(StoreClient.live.isLive)
    #expect(!StoreScript().client.isLive)
  }

  /// A hosted test target (KVExplorer's) drives StoreKit through an `SKTestSession`; `.live`
  /// would be idle there, so it needs StoreKit without the test-host rule.
  @Test("The StoreKit testing client is StoreKit, not marked live")
  func storeKitTestingIsNotLive() {
    #expect(!StoreClient.storeKitTesting.isLive)
  }
}
