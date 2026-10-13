import Foundation
import SupportKit
import Testing

@testable import SupportKitStore

@Suite("Pro store: entitlements")
@MainActor
struct ProStoreEntitlementTests {
  @Test("Forced unlocked is settled at once and Pro")
  func forcedUnlocked() async {
    let store = makeStore(StoreScript()) { $0.mode = .forced(isPro: true, price: nil) }
    #expect(store.isPro)
    #expect(store.unlockReason == .forced)
    #expect(store.purchaseState == .unlocked)
  }

  @Test("Forced locked shows the fixture price")
  func forcedLocked() {
    let store = makeStore(StoreScript()) { $0.mode = .forced(isPro: false, price: "$9.99") }
    #expect(!store.isPro)
    #expect(store.purchaseState == .locked(price: "$9.99"))
  }

  @Test("Forced mode never asks the store")
  func forcedModeNeverAsksTheStore() async {
    let script = StoreScript()
    let store = makeStore(script) { $0.mode = .forced(isPro: false, price: "$9.99") }
    store.start()
    await store.settled()
    #expect(await script.productRequests == 0)
    #expect(await script.entitlementRequests == 0)
    #expect(await script.syncs == 0)
  }

  @Test("A test host with the live client starts nothing and settles locked")
  func testHostStaysIdle() {
    let store = ProStore(.init(productID: "pro"), client: .live, isTestHost: true)
    store.start()
    #expect(!store.isPro)
    #expect(store.purchaseState == .locked(price: nil))
  }

  @Test("A test host with an injected client runs the live lifecycle")
  func testHostRunsAnInjectedClient() async {
    let script = StoreScript()
    await script.setEntitlements([script.transaction("pro")])
    let store = ProStore(
      .init(productID: "pro", defaults: scratchDefaults()), client: script.client,
      isTestHost: true)
    store.start()
    await store.settled()
    #expect(store.isPro)
  }

  @Test("Unknown until StoreKit has answered")
  func unknownBeforeStart() {
    #expect(makeStore(StoreScript()).purchaseState == .unknown)
  }

  @Test("A verified entitlement unlocks as purchased")
  func verifiedEntitlementUnlocks() async {
    let script = StoreScript()
    await script.setEntitlements([script.transaction("pro")])
    let store = makeStore(script)
    store.start()
    await store.settled()
    #expect(store.isPro)
    #expect(store.unlockReason == .purchased)
  }

  @Test("A retired product id still unlocks")
  func retiredProductStillEntitles() async {
    let script = StoreScript()
    await script.setEntitlements([script.transaction("old")])
    let store = makeStore(script) { $0.alsoEntitling = ["old"] }
    store.start()
    await store.settled()
    #expect(store.isPro)
  }

  @Test("A revoked entitlement does not unlock")
  func revokedDoesNotUnlock() async {
    let script = StoreScript()
    await script.setEntitlements([script.transaction("pro", revoked: true)])
    let store = makeStore(script)
    store.start()
    await store.settled()
    #expect(!store.isPro)
    #expect(store.isEntitlementResolved)
  }

  @Test("Unfinished transactions are granted and finished at launch")
  func unfinishedAreDrained() async {
    let script = StoreScript()
    await script.setUnfinished([.verified(script.transaction("pro")), .unverified])
    await script.setEntitlements([script.transaction("pro")])
    let store = makeStore(script)
    store.start()
    await store.settled()
    #expect(store.isPro)
    #expect(await script.finished == ["pro"])
  }

  /// A purchase that completed while the app was closed (an approved Ask to Buy, a deferred
  /// payment) waits in `unfinished`, and `currentEntitlements` can lag behind it: the read
  /// that follows the grant must not take it back, nor cache the lock.
  @Test("An unfinished purchase granted at launch survives an entitlement read that lags")
  func unfinishedGrantSurvivesALaggingRead() async {
    let script = StoreScript()
    await script.setUnfinished([.verified(script.transaction("pro"))])
    let defaults = scratchDefaults()
    let store = makeStore(script) {
      $0.cacheKey = "pro.cache"
      $0.defaults = defaults
    }
    store.start()
    await store.settled()
    #expect(store.isPro)
    #expect(defaults.bool(forKey: "pro.cache"))
  }

  @Test("An unfinished purchase granted by Restore survives an entitlement read that lags")
  func restoredUnfinishedGrantSurvivesALaggingRead() async {
    let script = StoreScript()
    let store = makeStore(script)
    store.start()
    await store.settled()
    await script.setUnfinished([.verified(script.transaction("pro"))])
    await store.restore()
    #expect(store.isPro)
    #expect(store.lastError == nil)
  }

  @Test("A cached unlock shows Unlocked before StoreKit answers")
  func cachedUnlockShowsAtOnce() {
    let defaults = scratchDefaults()
    defaults.set(true, forKey: "pro.cache")
    let store = ProStore(
      .init(productID: "pro", cacheKey: "pro.cache", defaults: defaults),
      client: StoreScript().client, isTestHost: false)
    #expect(store.purchaseState == .unlocked)
  }

  @Test("A stale cached unlock is corrected once StoreKit answers")
  func aStaleCachedUnlockIsCorrected() async {
    let defaults = scratchDefaults()
    defaults.set(true, forKey: "pro.cache")
    let store = ProStore(
      .init(productID: "pro", cacheKey: "pro.cache", defaults: defaults),
      client: StoreScript().client, isTestHost: false)
    store.start()
    await store.settled()
    #expect(!store.isPro)
    #expect(defaults.bool(forKey: "pro.cache") == false)
  }

  @Test("A cached lock stays unknown until StoreKit answers")
  func cachedLockStaysUnknown() {
    let defaults = scratchDefaults()
    defaults.set(false, forKey: "pro.cache")
    let store = ProStore(
      .init(productID: "pro", cacheKey: "pro.cache", defaults: defaults),
      client: StoreScript().client, isTestHost: false)
    #expect(store.purchaseState == .unknown)
  }

  @Test(
    "Upgrade from a paid app: production, at or below the cutoff",
    arguments: [
      (OriginalPurchase.production(originalAppVersion: "1.2.0"), true),
      (.production(originalAppVersion: "1.2.2"), true),
      (.production(originalAppVersion: "1.3.0"), false),
      (.notProduction, false),
    ])
  func upgradeFromPaid(original: OriginalPurchase, unlocks: Bool) async {
    let script = StoreScript()
    await script.setOriginal(original)
    let store = makeStore(script) { $0.upgradeFromPaid = "1.2.2" }
    store.start()
    await store.settled()
    #expect(store.isPro == unlocks)
    #expect(store.unlockReason == (unlocks ? .upgradedFromPaid : nil))
  }

  @Test("An inconclusive upgrade check keeps the cached unlock")
  func anInconclusiveUpgradeCheckKeepsTheCachedUnlock() async {
    let script = StoreScript()
    await script.setOriginal(.inconclusive)
    let defaults = scratchDefaults()
    defaults.set(true, forKey: "pro.cache")
    let store = ProStore(
      .init(productID: "pro", upgradeFromPaid: "1.2.2", cacheKey: "pro.cache", defaults: defaults),
      client: script.client, isTestHost: false)
    store.start()
    await store.settled()
    #expect(store.isPro)
    #expect(defaults.bool(forKey: "pro.cache"))
  }

  @Test(
    "Versions compare component by component",
    arguments: [
      ("1.1.0", "1.1.0", true), ("1.0.9", "1.1.0", true), ("1.1", "1.1.0", true),
      ("1.1.1", "1.1.0", false), ("2.0", "1.9.9", false),
      // iOS reports the build number: it never compares as an early marketing version.
      ("312", "1.2.2", false),
    ])
  func versionComparison(version: String, cutoff: String, isAtMost: Bool) {
    #expect(ProStore.version(version, isAtMost: cutoff) == isAtMost)
  }

  /// The read has to be in flight before the grant lands, or it starts after it and is not
  /// the race this guards.
  @Test("A slow read that began before a grant cannot undo it")
  func slowReadCannotUndoAGrant() async {
    let script = StoreScript()
    let gate = await script.gateEntitlements()
    let store = makeStore(script)
    store.start()
    #expect(await eventually { await script.entitlementRequests == 1 })
    script.updatesContinuation.yield(.verified(script.transaction("pro")))
    #expect(await eventually { store.isPro })
    gate.open()
    await store.settled()
    #expect(store.isPro)
  }

  @Test("A slow first read cannot undo a restore that answered first")
  func slowFirstReadCannotUndoARestore() async {
    let script = StoreScript()
    let gate = await script.gateEntitlements()
    let defaults = scratchDefaults()
    let store = makeStore(script) {
      $0.cacheKey = "pro.cache"
      $0.defaults = defaults
    }
    store.start()
    #expect(await eventually { await script.entitlementRequests == 1 })
    await script.setEntitlements([script.transaction("pro")])
    await store.restore()
    #expect(store.isPro)
    gate.open()
    await store.settled()
    #expect(store.isPro)
    #expect(defaults.bool(forKey: "pro.cache"))
  }

  @Test("An older read that saw the purchase cannot undo a refund read after it")
  func olderReadCannotUndoARefund() async {
    let script = StoreScript()
    await script.setEntitlements([script.transaction("pro")])
    let gate = await script.gateEntitlements()
    let defaults = scratchDefaults()
    defaults.set(true, forKey: "pro.cache")
    let store = makeStore(script) {
      $0.cacheKey = "pro.cache"
      $0.defaults = defaults
    }
    store.start()
    #expect(await eventually { await script.entitlementRequests == 1 })
    await script.setEntitlements([])
    script.updatesContinuation.yield(.verified(script.transaction("pro", revoked: true)))
    #expect(await eventually { !store.isPro })
    gate.open()
    await store.settled()
    #expect(!store.isPro)
    #expect(!defaults.bool(forKey: "pro.cache"))
  }

  @Test("A cancelled read settles nothing")
  func cancelledReadSettlesNothing() async {
    let script = StoreScript()
    await script.setEntitlements([script.transaction("pro")])
    let gate = await script.gateEntitlements()
    let store = makeStore(script)
    let read = Task { await store.refresh() }
    read.cancel()
    gate.open()
    await read.value
    #expect(!store.isPro)
  }

  @Test("A revocation re-reads every entitlement")
  func revocationReReads() async {
    let script = StoreScript()
    await script.setEntitlements([script.transaction("pro")])
    let store = makeStore(script)
    store.start()
    await store.settled()
    #expect(store.isPro)
    await script.setEntitlements([])
    script.updatesContinuation.yield(.verified(script.transaction("pro", revoked: true)))
    #expect(await eventually { !store.isPro })
  }

  @Test("A revoked Family Sharing grant keeps the person's own purchase")
  func revokedFamilyGrantKeepsOwnPurchase() async {
    let script = StoreScript()
    await script.setEntitlements([script.transaction("pro")])
    let store = makeStore(script)
    store.start()
    await store.settled()
    script.updatesContinuation.yield(.verified(script.transaction("pro", revoked: true)))
    #expect(await eventually { await script.finished == ["pro"] })
    #expect(store.isPro)
  }

  @Test("Updates for other products are finished, not granted")
  func otherProductsFinishedNotGranted() async {
    let script = StoreScript()
    let store = makeStore(script)
    store.start()
    await store.settled()
    script.updatesContinuation.yield(.verified(script.transaction("tip")))
    #expect(await eventually { await script.finished == ["tip"] })
    #expect(!store.isPro)
  }

  @Test("onChange fires on real changes only, never for the initial value")
  func onChangeFiresOnChanges() async {
    let script = StoreScript()
    await script.setEntitlements([script.transaction("pro")])
    let seen = Recorder()
    let store = makeStore(script) { $0.onChange = { seen.values.append($0) } }
    #expect(seen.values.isEmpty)
    store.start()
    await store.settled()
    await store.refresh()
    #expect(seen.values == [true])
  }

  @Test("hasEntitlement reads without a store")
  func hasEntitlementReadsWithoutAStore() async {
    let script = StoreScript()
    await script.setEntitlements([script.transaction("pro")])
    #expect(await ProStore.hasEntitlement(["pro"], client: script.client))
  }
}
