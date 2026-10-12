import Testing

@testable import SupportKitStore

@Suite("Pro store: purchase and restore")
@MainActor
struct ProStorePurchaseTests {
  /// A store whose first read and product load have settled, selling `product`.
  func readyStore(_ script: StoreScript, _ product: ProductInfo) async -> ProStore {
    await script.setProducts([product])
    let store = makeStore(script)
    store.start()
    await store.settled()
    return store
  }

  @Test("A verified purchase unlocks at once and is finished")
  func verifiedPurchaseUnlocks() async {
    let script = StoreScript()
    let store = await readyStore(script, script.product(outcome: .verified(script.transaction())))
    await store.purchase()
    #expect(store.isPro)
    #expect(store.unlockReason == .purchased)
    #expect(await script.finished == ["pro"])
    #expect(!store.isWorking)
  }

  @Test("An unverified purchase is an error and is not finished")
  func unverifiedIsAnError() async {
    let script = StoreScript()
    let store = await readyStore(
      script, script.product(outcome: .unverified(reason: "Bad receipt")))
    await store.purchase()
    #expect(!store.isPro)
    #expect(store.lastError?.contains("Bad receipt") == true)
    #expect(await script.finished.isEmpty)
  }

  @Test("Pending is a note, not an error")
  func pendingIsANote() async {
    let script = StoreScript()
    let store = await readyStore(script, script.product(outcome: .pending))
    await store.purchase()
    #expect(store.isPurchasePending)
    #expect(store.lastError == nil)
    #expect(!store.isPro)
  }

  @Test("An approved Ask to Buy clears the pending note")
  func approvalClearsPending() async {
    let script = StoreScript()
    let store = await readyStore(script, script.product(outcome: .pending))
    await store.purchase()
    script.updatesContinuation.yield(.verified(script.transaction()))
    #expect(await eventually { store.isPro })
    #expect(!store.isPurchasePending)
  }

  @Test("Cancelling changes nothing")
  func cancellingChangesNothing() async {
    let script = StoreScript()
    let store = await readyStore(script, script.product(outcome: .cancelled))
    await store.purchase()
    #expect(!store.isPro)
    #expect(store.lastError == nil)
    #expect(!store.isPurchasePending)
  }

  @Test("A thrown error is shown")
  func thrownErrorIsShown() async {
    let script = StoreScript()
    let store = await readyStore(script, script.failingProduct())
    await store.purchase()
    #expect(store.lastError != nil)
  }

  @Test("Buying with no product asks the store again before explaining")
  func buyingWithoutAProductRetriesFirst() async {
    let script = StoreScript()
    await script.failProducts()
    let store = makeStore(script)
    store.start()
    await store.settled()
    await store.purchase()
    #expect(await script.productRequests == 2)
    #expect(store.lastError != nil)
  }

  @Test("A second purchase while working is ignored")
  func aSecondPurchaseWhileWorkingIsIgnored() async {
    let script = StoreScript()
    let gate = Gate()
    let store = await readyStore(
      script, script.product(outcome: .verified(script.transaction()), gate: gate))
    let first = Task { await store.purchase() }
    #expect(await eventually { store.isWorking })
    await store.purchase()
    gate.open()
    await first.value
    #expect(await script.purchases == 1)
    #expect(store.isPro)
  }

  @Test("Restore unlocks from what the sync brings back")
  func restoreUnlocks() async {
    let script = StoreScript()
    let store = await readyStore(script, script.product(outcome: .cancelled))
    await script.setEntitlements([script.transaction()])
    await store.restore()
    #expect(store.isPro)
    #expect(await script.syncs == 1)
    #expect(store.lastError == nil)
  }

  @Test("Restore finishes unfinished transactions")
  func restoreFinishesUnfinished() async {
    let script = StoreScript()
    let store = await readyStore(script, script.product(outcome: .cancelled))
    await script.setUnfinished([.verified(script.transaction())])
    await script.setEntitlements([script.transaction()])
    await store.restore()
    #expect(await script.finished == ["pro"])
  }

  @Test("Restore finding nothing says so")
  func restoreFindingNothingSaysSo() async {
    let script = StoreScript()
    let store = await readyStore(script, script.product(outcome: .cancelled))
    await store.restore()
    #expect(!store.isPro)
    #expect(store.lastError != nil)
  }

  @Test("A failed sync is shown")
  func failedSyncIsShown() async {
    let script = StoreScript()
    let store = await readyStore(script, script.product(outcome: .cancelled))
    await script.failSync()
    await store.restore()
    #expect(store.lastError != nil)
  }

  @Test("Dismissing the sign-in prompt on Restore is not an error")
  func cancelledRestoreIsNotAnError() async {
    let script = StoreScript()
    let store = await readyStore(script, script.product(outcome: .cancelled))
    await script.cancelSync()
    await store.restore()
    #expect(store.lastError == nil)
    #expect(!store.isWorking)
  }

  @Test("A purchase cancelled by a throw is not an error")
  func cancelledPurchaseThrowIsNotAnError() async {
    let script = StoreScript()
    let store = await readyStore(script, script.failingProduct(CancellationError()))
    await store.purchase()
    #expect(store.lastError == nil)
  }

  @Test("clearError clears")
  func clearErrorClears() async {
    let script = StoreScript()
    let store = await readyStore(script, script.failingProduct())
    await store.purchase()
    store.clearError()
    #expect(store.lastError == nil)
  }

  @Test("Forced mode neither buys nor restores")
  func forcedNeitherBuysNorRestores() async {
    let script = StoreScript()
    let store = makeStore(script) { $0.mode = .forced(isPro: false, price: "$9.99") }
    await store.purchase()
    await store.restore()
    #expect(await script.purchases == 0)
    #expect(await script.syncs == 0)
  }
}
