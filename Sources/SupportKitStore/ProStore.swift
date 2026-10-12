import Foundation
import Observation
import SupportKit
import os

let storeLog = Logger(subsystem: "io.mgcrea.SupportKitStore", category: "pro")

/// The Pro unlock: one non-consumable, what the App Store says about it, and buying and
/// restoring it. Every app in the fleet sells exactly this, so the lifecycle lives here once;
/// what differs per app is in `Configuration`.
///
/// It owns the first entitlement read (a closing window cannot cancel it), retries a product
/// that did not load each time `start()` is called, grants straight from a verified purchase
/// (`currentEntitlements` lags behind one), and never lets a read that began before a grant
/// undo it. The paywall flag, the gate and partial grandfathering stay in each app, built on
/// `isPro`.
///
/// Under a test host (`XCTestConfigurationFilePath` set), the `.live` client starts nothing
/// and settles locked, so a hosted test never reaches StoreKit or reads the machine's
/// purchases. A suite that drives StoreKit through an `SKTestSession` passes
/// `.storeKitTesting`; any other injected client runs the live lifecycle against it.
@Observable
@MainActor
public final class ProStore {
  public enum Mode: Sendable, Equatable {
    case live
    /// No StoreKit, settled at once. Screenshots and demo mode pass a fixture price; an app
    /// not selling yet passes `.forced(isPro: true, price: nil)`.
    case forced(isPro: Bool, price: String?)
  }

  public enum UnlockReason: Sendable, Equatable {
    case purchased
    case upgradedFromPaid
    case forced
  }

  /// Built on the main actor, which is why it is not `Sendable`: it carries `UserDefaults`.
  public struct Configuration {
    public var productID: String
    /// Retired product ids that still grant Pro.
    public var alsoEntitling: Set<String>
    public var mode: Mode
    /// Buyers of the paid app before this version get Pro: compared, component by component,
    /// with `AppTransaction.originalAppVersion`, in the production environment only. That is
    /// the marketing version on macOS but the **build number** on iOS.
    public var upgradeFromPaid: String?
    /// Caches the answer for a correct first frame. A cached `true` shows Unlocked at once;
    /// a cached `false` shows unknown until StoreKit answers.
    public var cacheKey: String?
    public var defaults: UserDefaults
    /// Called on every change of `isPro`, after the state is updated, never for the
    /// initial value.
    public var onChange: (@MainActor (Bool) -> Void)?

    public init(
      productID: String,
      alsoEntitling: Set<String> = [],
      mode: Mode = .live,
      upgradeFromPaid: String? = nil,
      cacheKey: String? = nil,
      defaults: UserDefaults = .standard,
      onChange: (@MainActor (Bool) -> Void)? = nil
    ) {
      self.productID = productID
      self.alsoEntitling = alsoEntitling
      self.mode = mode
      self.upgradeFromPaid = upgradeFromPaid
      self.cacheKey = cacheKey
      self.defaults = defaults
      self.onChange = onChange
    }
  }

  public private(set) var isPro = false
  public private(set) var displayPrice: String?
  public private(set) var isLoadingProduct = false
  public private(set) var unlockReason: UnlockReason?
  /// A purchase or restore is in flight.
  public private(set) var isWorking = false
  /// Ask to Buy, or a deferred payment: a note, never an error.
  public private(set) var isPurchasePending = false
  /// Worded and localized by the kit.
  public private(set) var lastError: String?
  private(set) var isEntitlementResolved = false
  private(set) var isProductAnswered = false

  @ObservationIgnored let configuration: Configuration
  @ObservationIgnored let client: StoreClient
  @ObservationIgnored private let isIdle: Bool
  @ObservationIgnored var product: ProductInfo?
  @ObservationIgnored var productLoad: Task<Void, Never>?
  @ObservationIgnored private var firstRead: Task<Void, Never>?
  @ObservationIgnored private var listener: Task<Void, Never>?
  @ObservationIgnored private var grants = 0
  @ObservationIgnored private var reads = 0
  /// How long a product lookup may take before it counts as unanswered.
  @ObservationIgnored var productTimeout: Duration = .seconds(30)

  public convenience init(_ configuration: Configuration, client: StoreClient = .live) {
    self.init(
      configuration, client: client,
      isTestHost: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil)
  }

  init(_ configuration: Configuration, client: StoreClient, isTestHost: Bool) {
    self.configuration = configuration
    self.client = client
    isIdle = client.isLive && isTestHost
    switch configuration.mode {
    case .forced(let isPro, let price):
      self.isPro = isPro
      unlockReason = isPro ? .forced : nil
      displayPrice = price
      isEntitlementResolved = true
      isProductAnswered = true
    case .live:
      if let key = configuration.cacheKey, configuration.defaults.bool(forKey: key) {
        isPro = true
      }
      if isIdle {
        isEntitlementResolved = true
        isProductAnswered = true
      }
    }
  }

  /// `.unlocked` when Pro; `.unknown` until the entitlement and the product lookup have both
  /// answered; otherwise `.locked(price:)`, where nil means the product did not load.
  public var purchaseState: ProPurchaseState {
    if isPro { return .unlocked }
    guard isEntitlementResolved, isProductAnswered else { return .unknown }
    return .locked(price: displayPrice)
  }

  /// The store answered and gave no product, and is not asking again right now. The views
  /// offer Try Again.
  public var isProductUnavailable: Bool {
    runsStoreKit && isProductAnswered && !isLoadingProduct && displayPrice == nil
  }

  /// Live, and not a test host running `.live`.
  var runsStoreKit: Bool {
    guard case .live = configuration.mode else { return false }
    return !isIdle
  }

  // MARK: - Lifecycle

  /// Idempotent. The app calls it at launch, and every view that wants a price calls it as
  /// it appears.
  public func start() {
    guard runsStoreKit else { return }
    if listener == nil {
      let updates = client.updates()
      listener = Task { [weak self] in
        for await update in updates { await self?.handle(update) }
      }
      firstRead = Task { [weak self] in await self?.readFirst() }
    }
    // The retry: a lookup that failed once (offline at launch, a storefront the product is
    // not sold in) would otherwise leave Unlock dead until the next launch.
    if product == nil, productLoad == nil { loadProduct() }
  }

  /// Waits for the work `start()` began. For tests.
  func settled() async {
    await firstRead?.value
    await productLoad?.value
  }

  private func readFirst() async {
    for update in await client.unfinished() { await handle(update) }
    await refresh()
  }

  /// Re-reads what the App Store says. Discarded when a grant landed meanwhile, when a later
  /// read started meanwhile (the newest question gets the last word: a first read that stalled
  /// must not undo a restore, nor an old read that saw a purchase undo the refund after it),
  /// and when the task was cancelled.
  func refresh() async {
    reads += 1
    let read = reads
    let generation = grants
    let purchased = await client.isEntitled(to: entitlingIDs)
    var upgraded: Bool? = false
    if !purchased, let cutoff = configuration.upgradeFromPaid {
      switch await client.originalPurchase() {
      case .production(let original): upgraded = Self.version(original, isAtMost: cutoff)
      case .notProduction: upgraded = false
      case .inconclusive: upgraded = nil
      }
    }
    guard !Task.isCancelled, read == reads, grants == generation else { return }
    isEntitlementResolved = true
    if purchased {
      apply(true, reason: .purchased)
    } else if upgraded == true {
      apply(true, reason: .upgradedFromPaid)
    } else if upgraded == false {
      apply(false, reason: nil)
    }
    // nil: inconclusive, so whatever was known stands.
  }

  private func handle(_ update: TransactionUpdate) async {
    guard case .verified(let transaction) = update else { return }
    if entitles(transaction.productID) {
      if transaction.isRevoked {
        // A revoked Family Sharing grant must not remove the person's own purchase.
        await refresh()
      } else {
        grant()
      }
    }
    await transaction.finish()
  }

  func grant() {
    grants += 1
    apply(true, reason: .purchased)
  }

  private func apply(_ value: Bool, reason: UnlockReason?) {
    let changed = value != isPro
    isEntitlementResolved = true
    isPro = value
    unlockReason = value ? reason : nil
    if value {
      isPurchasePending = false
      lastError = nil
    }
    if let key = configuration.cacheKey { configuration.defaults.set(value, forKey: key) }
    if changed { configuration.onChange?(value) }
  }

  private var entitlingIDs: Set<String> {
    configuration.alsoEntitling.union([configuration.productID])
  }

  func entitles(_ productID: String) -> Bool { entitlingIDs.contains(productID) }

  // MARK: - Product

  /// Returns at once when the product is loaded; waits for a load already in flight; otherwise
  /// starts one and waits for it.
  public func ensureProduct() async {
    guard runsStoreKit, product == nil else { return }
    if productLoad == nil { loadProduct() }
    await productLoad?.value
  }

  private func loadProduct() {
    isLoadingProduct = true
    let client = client
    let id = configuration.productID
    let timeout = productTimeout
    productLoad = Task { [weak self] in
      var answer: ProductInfo?
      do {
        answer = try await Self.answer(within: timeout) { try await client.products([id]) }.first
        if answer == nil {
          storeLog.error("The App Store returned no product \(id, privacy: .public)")
        }
      } catch {
        storeLog.error(
          "Loading \(id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
      }
      self?.finishLoading(answer)
    }
  }

  struct TimedOut: Error {}

  /// Races `operation` against `timeout`. Not a task group, which would wait at its end for an
  /// operation that ignores cancellation: a lookup that never answers is the case this is for.
  nonisolated static func answer<T: Sendable>(
    within timeout: Duration, _ operation: @escaping @Sendable () async throws -> T
  ) async throws -> T {
    let pending = OSAllocatedUnfairLock<CheckedContinuation<T, any Error>?>(initialState: nil)
    return try await withCheckedThrowingContinuation { continuation in
      pending.withLock { $0 = continuation }
      let timer = Task {
        try? await Task.sleep(for: timeout)
        pending.withLock { $0.take() }?.resume(throwing: TimedOut())
      }
      Task {
        let result: Result<T, any Error>
        do { result = .success(try await operation()) } catch { result = .failure(error) }
        timer.cancel()
        pending.withLock { $0.take() }?.resume(with: result)
      }
    }
  }

  /// `isProductAnswered` is never reset, so a retry that fails keeps `.locked(price: nil)`
  /// rather than going back to `.unknown`, which would take every PRO badge away while it runs.
  private func finishLoading(_ answer: ProductInfo?) {
    product = answer
    displayPrice = answer?.displayPrice
    isProductAnswered = true
    isLoadingProduct = false
    productLoad = nil
  }

  // MARK: - Purchase

  /// Buys. Asks the store for the product again first when it has none. Ignored while a
  /// purchase or restore is in flight.
  public func purchase() async {
    guard runsStoreKit, !isWorking else { return }
    isWorking = true
    lastError = nil
    isPurchasePending = false
    defer { isWorking = false }
    await ensureProduct()
    guard let product else {
      lastError = localized("The App Store did not return the purchase. Try again in a moment.")
      return
    }
    do {
      switch try await product.purchase() {
      case .verified(let transaction):
        // Granted here, not re-read: `currentEntitlements` lags behind a purchase.
        if !transaction.isRevoked, entitles(transaction.productID) { grant() }
        await transaction.finish()
      case .unverified(let reason):
        lastError = localized("The purchase could not be verified: \(reason)")
      case .pending:
        isPurchasePending = true
      case .cancelled:
        break
      }
    } catch is CancellationError {
      // Dismissed, by the person or by the task: nothing to say.
    } catch {
      lastError = error.localizedDescription
    }
  }

  /// `AppStore.sync()`, then what it brought back. Says so when there is still nothing.
  public func restore() async {
    guard runsStoreKit, !isWorking else { return }
    isWorking = true
    lastError = nil
    defer { isWorking = false }
    do {
      try await client.sync()
    } catch is CancellationError {
      // The person dismissed the sign-in prompt: they chose not to restore.
      return
    } catch {
      lastError = error.localizedDescription
    }
    for update in await client.unfinished() { await handle(update) }
    await refresh()
    if !isPro, lastError == nil {
      lastError = localized("No previous purchase was found on this Apple Account.")
    }
  }

  /// For an app whose paywall opens on a stale error from an earlier attempt.
  public func clearError() {
    lastError = nil
  }

  // MARK: - Without a store

  /// For App Intents and share extensions: a verified, unrevoked purchase of any of
  /// `productIDs`.
  public nonisolated static func hasEntitlement(_ productIDs: Set<String>) async -> Bool {
    await hasEntitlement(productIDs, client: .live)
  }

  nonisolated static func hasEntitlement(_ productIDs: Set<String>, client: StoreClient) async
    -> Bool
  {
    await client.isEntitled(to: productIDs)
  }

  /// Component by component; a missing component is 0, a non-numeric one is 0.
  nonisolated static func version(_ version: String, isAtMost cutoff: String) -> Bool {
    let lhs = version.split(separator: ".").map { Int($0) ?? 0 }
    let rhs = cutoff.split(separator: ".").map { Int($0) ?? 0 }
    for index in 0..<max(lhs.count, rhs.count) {
      let left = index < lhs.count ? lhs[index] : 0
      let right = index < rhs.count ? rhs[index] : 0
      if left != right { return left < right }
    }
    return true
  }
}
