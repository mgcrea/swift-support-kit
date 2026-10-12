import SupportKit
import Testing

@testable import SupportKitStore

@Suite("Pro store: product")
@MainActor
struct ProStoreProductTests {
  @Test("Starting loads the price")
  func startLoadsThePrice() async {
    let script = StoreScript()
    await script.setProducts([script.product(outcome: .cancelled)])
    let store = makeStore(script)
    store.start()
    await store.settled()
    #expect(store.displayPrice == "$5.99")
    #expect(store.purchaseState == .locked(price: "$5.99"))
    #expect(!store.isProductUnavailable)
  }

  @Test("A failed load is Unavailable, and the next start asks again")
  func failedLoadIsRetriedOnTheNextStart() async {
    let script = StoreScript()
    await script.failProducts()
    let store = makeStore(script)
    store.start()
    await store.settled()
    #expect(store.isProductUnavailable)
    #expect(store.purchaseState == .locked(price: nil))
    await script.setProducts([script.product(outcome: .cancelled)])
    store.start()
    await store.settled()
    #expect(store.displayPrice == "$5.99")
    #expect(await script.productRequests == 2)
  }

  @Test("An empty answer is Unavailable")
  func emptyAnswerIsUnavailable() async {
    let store = makeStore(StoreScript())
    store.start()
    await store.settled()
    #expect(store.isProductUnavailable)
    #expect(store.purchaseState == .locked(price: nil))
  }

  @Test("A failed retry stays locked, never back to unknown")
  func failedRetryStaysLocked() async {
    let script = StoreScript()
    await script.failProducts()
    let store = makeStore(script)
    store.start()
    await store.settled()
    let gate = await script.gateProducts()
    store.start()
    #expect(store.purchaseState == .locked(price: nil))
    #expect(!store.isProductUnavailable)
    gate.open()
    await store.settled()
    #expect(store.purchaseState == .locked(price: nil))
    #expect(store.isProductUnavailable)
  }

  @Test("ensureProduct waits for the load already in flight")
  func ensureProductWaitsForTheLoadInFlight() async {
    let script = StoreScript()
    await script.setProducts([script.product(outcome: .cancelled)])
    let gate = await script.gateProducts()
    let store = makeStore(script)
    store.start()
    let waiting = Task { await store.ensureProduct() }
    gate.open()
    await waiting.value
    #expect(store.displayPrice == "$5.99")
    #expect(await script.productRequests == 1)
  }

  @Test("Starting again while loading does not stack requests")
  func startingAgainWhileLoadingDoesNotStackRequests() async {
    let script = StoreScript()
    await script.setProducts([script.product(outcome: .cancelled)])
    let gate = await script.gateProducts()
    let store = makeStore(script)
    store.start()
    store.start()
    store.start()
    gate.open()
    await store.settled()
    #expect(await script.productRequests == 1)
  }

  @Test("A loaded product is not loaded again")
  func loadedProductIsNotReloaded() async {
    let script = StoreScript()
    await script.setProducts([script.product(outcome: .cancelled)])
    let store = makeStore(script)
    store.start()
    await store.settled()
    store.start()
    await store.ensureProduct()
    await store.settled()
    #expect(await script.productRequests == 1)
  }

  @Test("A lookup that never answers times out as Unavailable, and Try Again asks again")
  func aLookupThatNeverAnswersTimesOut() async {
    let script = StoreScript()
    _ = await script.gateProducts()
    let store = makeStore(script)
    store.productTimeout = .milliseconds(50)
    store.start()
    await store.settled()
    #expect(store.isProductUnavailable)
    #expect(store.purchaseState == .locked(price: nil))
    await script.setProducts([script.product(outcome: .cancelled)])
    store.start()
    await store.settled()
    #expect(store.displayPrice == "$5.99")
    #expect(await script.productRequests == 2)
  }

  @Test("Forced mode is never Unavailable")
  func forcedIsNeverUnavailable() {
    let store = makeStore(StoreScript()) { $0.mode = .forced(isPro: false, price: nil) }
    #expect(!store.isProductUnavailable)
  }
}
