# SupportKitStore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship swift-support-kit 1.21.0 with a shared StoreKit Pro store (`SupportKitStore`) and a Try Again / pending note in the kit's existing upgrade sheet and Pro pane.

**Architecture:** A new `SupportKitStore` product holds one `@Observable @MainActor` `ProStore` that owns the whole purchase lifecycle, configured per app. Every StoreKit call goes through a `StoreClient` struct of closures trafficking in the store's own value types, so the lifecycle is unit-tested against a scripted client; `.live` wraps StoreKit. `ProPurchaseState` moves to the Foundation-only `SupportKit` so the store can produce it without SwiftUI.

**Tech Stack:** Swift 6.4 toolchain, swift-tools 6.0, StoreKit 2, Observation, Swift Testing, StoreKitTest (spike only).

**Spec:** `docs/superpowers/specs/2026-10-12-pro-store-design.md`

## Global Constraints

- Platforms stay `macOS("26.0")`, `iOS("26.0")`; swift-tools-version 6.0.
- `SupportKitStore` depends on `SupportKit` only, imports StoreKit, Foundation, Observation and os; never SwiftUI.
- Every string a module shows goes through that module's `localized(_:)` against `.module`, has an entry in that module's `Resources/Localizable.xcstrings` with `"extractionState": "manual"`, `"generatesSymbol": false` and a `fr` translation in the catalog's existing typography (check a neighbouring entry: apostrophes are `’`).
- UI changes are additive: every existing call site of `ProUpgradeSheet`, `ProSettingsPane`, `ProBadge` and `ProPurchaseState` compiles and behaves exactly as before.
- `xcrun swift-format lint --strict --recursive Package.swift Sources Tests` passes (2-space indent, 100 columns), as CI runs it.
- Baseline before any change: `swift test` green, 176 tests. The suite stays green after every task.
- Commit messages follow the repo: `feat(SupportKitStore): …`, `feat(SupportKitSettings): …`, `docs: …`, full sentences saying why.
- Nothing is pushed and no tag leaves the machine; Task 8 tags locally.

## Review Focus

1. A cached `true` while StoreKit, once asked, finds no purchase (refunded while offline): the store must end locked and rewrite the cache, never stay unlocked on a stale flag. Test: Task 3 `aStaleCachedUnlockIsCorrected`.
2. `upgradeFromPaid` set, cached `true`, and the App Store's original-purchase record unreachable: an inconclusive answer must keep Pro, not lock a paying customer out. Test: Task 3 `anInconclusiveUpgradeCheckKeepsTheCachedUnlock`.
3. Unlock tapped twice quickly: one App Store purchase, not two sheets. Test: Task 5 `aSecondPurchaseWhileWorkingIsIgnored`.
4. Several views calling `start()` while the product is still loading (paywall, pane, badge all appearing at once): one request, not one per view. Test: Task 4 `startingAgainWhileLoadingDoesNotStackRequests`.
5. Forced mode (screenshots, demo, not selling yet) with views still calling `start()`, `ensureProduct()`, `purchase()` and `restore()`: StoreKit is never touched. Test: Task 3 `forcedModeNeverAsksTheStore`.

Also documented, not testable in the kit: `originalAppVersion` is the marketing version on macOS and the **build number** on iOS, so `upgradeFromPaid` compares like with like only on the Mac. Task 3's doc comment and Task 8's README say so.

---

### Task 1: `ProPurchaseState` moves to `SupportKit`

**Files:**
- Create: `Sources/SupportKit/ProPurchaseState.swift`
- Modify: `Sources/SupportKitSettings/ProSettingsPane.swift` (remove the enum, lines 67-76 today: the doc comment from "/// Where the purchase stands" to the closing brace)
- Create: `Tests/SupportKitTests/ProPurchaseStateTests.swift`
- Create: `Tests/SupportKitSettingsTests/ProPurchaseStateVisibilityTests.swift`

**Interfaces:**
- Produces: `public enum ProPurchaseState: Sendable, Equatable { case unknown; case locked(price: String?); case unlocked }` in module `SupportKit`, still nameable from a file that imports only `SupportKitSettings`.

- [ ] **Step 1: Write the failing tests**

`Tests/SupportKitTests/ProPurchaseStateTests.swift`:

```swift
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
```

`Tests/SupportKitSettingsTests/ProPurchaseStateVisibilityTests.swift`:

```swift
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
```

- [ ] **Step 2: Run them to see the first fail**

Run: `swift test --filter "ProPurchaseState"`
Expected: build failure in `SupportKitTests`: `'ProPurchaseState' is not a member type of module 'SupportKit'`. The visibility test compiles today (the enum is still in Settings).

- [ ] **Step 3: Move the enum**

Create `Sources/SupportKit/ProPurchaseState.swift` with the enum and its doc comment moved verbatim from `ProSettingsPane.swift`:

```swift
/// Where the purchase stands, as far as the pane needs to know.
///
/// Three cases rather than a `Bool`, for the reason balise's `ProStatus` gives:
/// at launch the answer is not known yet, and drawing a Buy button during that
/// window offers Pro to somebody who has already paid.
///
/// In `SupportKit`, which is Foundation-only, so `SupportKitStore` can produce it
/// without SwiftUI. `SupportKitSettings` re-exports it.
public enum ProPurchaseState: Sendable, Equatable {
  case unknown
  /// `price` is the store's display price. Nil means the product did not load,
  /// which the pane says, rather than drawing a Buy button with no price on it.
  case locked(price: String?)
  case unlocked
}
```

Delete the same declaration (and its doc comment) from `Sources/SupportKitSettings/ProSettingsPane.swift`.

- [ ] **Step 4: Run, and re-export if the visibility test now fails**

Run: `swift test --filter "ProPurchaseState"`
Expected: `ProPurchaseStateTests` passes. If `ProPurchaseStateVisibilityTests` (or any Settings source) fails with `cannot find type 'ProPurchaseState' in scope`, add at the top of `Sources/SupportKitSettings/ProSettingsPane.swift`, below the existing imports:

```swift
/// `ProPurchaseState` moved to `SupportKit` in 1.21.0; apps that import only this module
/// still name it.
@_exported import enum SupportKit.ProPurchaseState
```

Run again. Expected: both pass. If a scoped `@_exported` import is rejected by the compiler, use `@_exported import SupportKit` instead and record the ruling.

- [ ] **Step 5: Full suite and lint**

Run: `swift test 2>&1 | grep -E "Test run with|error:"` and `xcrun swift-format lint --strict --recursive Package.swift Sources Tests`
Expected: 178 tests pass, no lint output.

- [ ] **Step 6: Commit**

```bash
git add Sources/SupportKit/ProPurchaseState.swift Sources/SupportKitSettings/ProSettingsPane.swift Tests/SupportKitTests/ProPurchaseStateTests.swift Tests/SupportKitSettingsTests/ProPurchaseStateVisibilityTests.swift
git commit -m "refactor(SupportKit): move ProPurchaseState into the Foundation-only module, so the store can produce it without SwiftUI, and keep it nameable from SupportKitSettings"
```

---

### Task 2: The `SupportKitStore` product and its StoreKit seam

**Files:**
- Modify: `Package.swift` (header comment, `products`, `targets`)
- Create: `Sources/SupportKitStore/StoreClient.swift`
- Create: `Sources/SupportKitStore/StoreClient+Live.swift`
- Create: `Sources/SupportKitStore/Localized.swift`
- Create: `Sources/SupportKitStore/Resources/Localizable.xcstrings`
- Modify: `Tests/SupportKitLocalizationTests/CatalogScanner.swift:22-26`
- Create: `Tests/SupportKitStoreTests/StoreScript.swift`
- Create: `Tests/SupportKitStoreTests/StoreClientTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces (all `public`, module `SupportKitStore`):
  - `struct ProductInfo: Sendable { let id: String; let displayPrice: String; let purchase: @Sendable () async throws -> PurchaseOutcome; init(id:displayPrice:purchase:) }`
  - `struct TransactionInfo: Sendable { let productID: String; let isRevoked: Bool; let finish: @Sendable () async -> Void; init(productID:isRevoked:finish:) }`
  - `enum PurchaseOutcome: Sendable { case verified(TransactionInfo); case unverified(reason: String); case pending; case cancelled }`
  - `enum TransactionUpdate: Sendable { case verified(TransactionInfo); case unverified }`
  - `enum OriginalPurchase: Sendable, Equatable { case production(originalAppVersion: String); case notProduction; case inconclusive }`
  - `struct StoreClient: Sendable` with vars `products: @Sendable ([String]) async throws -> [ProductInfo]`, `currentEntitlements: @Sendable () async -> [TransactionInfo]`, `unfinished: @Sendable () async -> [TransactionUpdate]`, `updates: @Sendable () -> AsyncStream<TransactionUpdate>`, `sync: @Sendable () async throws -> Void`, `originalPurchase: @Sendable () async -> OriginalPurchase`; internal `let isLive: Bool`; `public init(products:currentEntitlements:unfinished:updates:sync:originalPurchase:)`; `static let live`; `func isEntitled(to productIDs: Set<String>) async -> Bool`.
  - Internal: `func localized(_ key: String.LocalizationValue) -> String`.
- Test support (module `SupportKitStoreTests`): `actor StoreScript`, `final class Gate`.

- [ ] **Step 1: Declare the product and target**

In `Package.swift`, change the header's first line from `// Seven products, deliberately split.` to `// Eight products, deliberately split.`, and add this paragraph after the `SupportKitModels` paragraph:

```swift
// `SupportKitStore` is the Pro purchase: StoreKit's half of what `SupportKitSettings`
// draws. Its own product because it links StoreKit, which an app wanting the Help menu
// should not pay for, and because it draws nothing: the sheet and the pane take values and
// closures, never a store, so the two halves stay independent and an app can adopt either.
```

Add to `products`, after `SupportKitModels`:

```swift
    .library(name: "SupportKitStore", targets: ["SupportKitStore"]),
```

Add to `targets`, after the `SupportKitModels` target:

```swift
    // A catalog: its purchase errors are shown to the user as they are.
    .target(
      name: "SupportKitStore",
      dependencies: ["SupportKit"],
      resources: [.process("Resources")]
    ),
```

and after `SupportKitModelsTests`:

```swift
    .testTarget(name: "SupportKitStoreTests", dependencies: ["SupportKitStore"]),
```

- [ ] **Step 2: Add the module's localization plumbing**

`Sources/SupportKitStore/Localized.swift`:

```swift
import Foundation

/// Looks a string up in **this module's** catalog. See `SupportKitUI`'s
/// `Localized.swift` for why every module that shows text carries its own copy.
func localized(_ key: String.LocalizationValue) -> String {
  String(localized: key, bundle: .module)
}
```

`Sources/SupportKitStore/Resources/Localizable.xcstrings`:

```json
{
  "sourceLanguage" : "en",
  "strings" : {

  },
  "version" : "1.0"
}
```

In `Tests/SupportKitLocalizationTests/CatalogScanner.swift`, add the module:

```swift
    static let ui = Module(name: "SupportKitUI")
    static let settings = Module(name: "SupportKitSettings")
    static let menuBar = Module(name: "SupportKitMenuBar")
    static let store = Module(name: "SupportKitStore")

    static let all: [Module] = [.ui, .settings, .menuBar, .store]
```

- [ ] **Step 3: Write the scripted client and the failing seam test**

`Tests/SupportKitStoreTests/StoreScript.swift`:

```swift
import Foundation

@testable import SupportKitStore

/// Holds one awaiting caller until opened. Opens once.
final class Gate: Sendable {
  private let stream: AsyncStream<Void>
  private let continuation: AsyncStream<Void>.Continuation

  init() { (stream, continuation) = AsyncStream.makeStream() }

  func wait() async { for await _ in stream { return } }
  func open() {
    continuation.yield()
    continuation.finish()
  }
}

/// A scripted App Store: what it answers, and a record of what it was asked.
actor StoreScript {
  struct Unreachable: Error {}

  private(set) var productRequests = 0
  private(set) var purchases = 0
  private(set) var syncs = 0
  private(set) var finished: [String] = []

  private var products: [ProductInfo] = []
  private var productError: (any Error)?
  private var productGate: Gate?
  private var entitlements: [TransactionInfo] = []
  private var entitlementGate: Gate?
  private var unfinished: [TransactionUpdate] = []
  private var original: OriginalPurchase = .notProduction
  private var syncError: (any Error)?

  nonisolated let updates: AsyncStream<TransactionUpdate>
  nonisolated let updatesContinuation: AsyncStream<TransactionUpdate>.Continuation

  init() { (updates, updatesContinuation) = AsyncStream.makeStream() }

  // MARK: Scripting

  func setProducts(_ products: [ProductInfo]) {
    self.products = products
    productError = nil
  }
  func failProducts() { productError = Unreachable() }
  func gateProducts() -> Gate {
    let gate = Gate()
    productGate = gate
    return gate
  }
  func setEntitlements(_ entitlements: [TransactionInfo]) { self.entitlements = entitlements }
  func gateEntitlements() -> Gate {
    let gate = Gate()
    entitlementGate = gate
    return gate
  }
  func setUnfinished(_ updates: [TransactionUpdate]) { unfinished = updates }
  func setOriginal(_ original: OriginalPurchase) { self.original = original }
  func failSync() { syncError = Unreachable() }

  // MARK: Values

  nonisolated func transaction(_ id: String = "pro", revoked: Bool = false) -> TransactionInfo {
    TransactionInfo(productID: id, isRevoked: revoked) { await self.recordFinish(id) }
  }

  nonisolated func product(
    price: String = "$5.99", outcome: PurchaseOutcome, gate: Gate? = nil
  ) -> ProductInfo {
    ProductInfo(id: "pro", displayPrice: price) {
      await self.recordPurchase()
      await gate?.wait()
      return outcome
    }
  }

  nonisolated func failingProduct() -> ProductInfo {
    ProductInfo(id: "pro", displayPrice: "$5.99") {
      await self.recordPurchase()
      throw Unreachable()
    }
  }

  // MARK: The client

  nonisolated var client: StoreClient {
    StoreClient(
      products: { _ in try await self.answerProducts() },
      currentEntitlements: { await self.answerEntitlements() },
      unfinished: { await self.takeUnfinished() },
      updates: { self.updates },
      sync: { try await self.answerSync() },
      originalPurchase: { await self.original })
  }

  private func answerProducts() async throws -> [ProductInfo] {
    productRequests += 1
    if let gate = productGate {
      productGate = nil
      await gate.wait()
    }
    if let productError { throw productError }
    return products
  }

  private func answerEntitlements() async -> [TransactionInfo] {
    if let gate = entitlementGate {
      entitlementGate = nil
      await gate.wait()
    }
    return entitlements
  }

  private func takeUnfinished() -> [TransactionUpdate] {
    defer { unfinished = [] }
    return unfinished
  }

  private func answerSync() throws {
    syncs += 1
    if let syncError { throw syncError }
  }

  private func recordFinish(_ id: String) { finished.append(id) }
  private func recordPurchase() { purchases += 1 }
}
```

`Tests/SupportKitStoreTests/StoreClientTests.swift`:

```swift
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
}
```

- [ ] **Step 4: Run to verify it fails**

Run: `swift test --filter SupportKitStoreTests`
Expected: build failure, `cannot find type 'StoreClient' in scope` (and the other value types).

- [ ] **Step 5: Write the seam**

`Sources/SupportKitStore/StoreClient.swift`:

```swift
import Foundation

/// The product, as much of it as the store needs. StoreKit's `Product` cannot be built in a
/// test, so the store never holds one.
public struct ProductInfo: Sendable {
  public let id: String
  public let displayPrice: String
  public let purchase: @Sendable () async throws -> PurchaseOutcome

  public init(
    id: String, displayPrice: String,
    purchase: @escaping @Sendable () async throws -> PurchaseOutcome
  ) {
    self.id = id
    self.displayPrice = displayPrice
    self.purchase = purchase
  }
}

/// A verified transaction, as much of it as the store needs.
public struct TransactionInfo: Sendable {
  public let productID: String
  public let isRevoked: Bool
  public let finish: @Sendable () async -> Void

  public init(productID: String, isRevoked: Bool, finish: @escaping @Sendable () async -> Void) {
    self.productID = productID
    self.isRevoked = isRevoked
    self.finish = finish
  }
}

/// What a purchase came back with.
public enum PurchaseOutcome: Sendable {
  case verified(TransactionInfo)
  /// StoreKit's reason, already a sentence.
  case unverified(reason: String)
  /// Ask to Buy, or a payment the bank defers. Neither success nor failure.
  case pending
  case cancelled
}

/// One transaction from `Transaction.updates` or `Transaction.unfinished`. An unverified one
/// is never granted and never finished.
public enum TransactionUpdate: Sendable {
  case verified(TransactionInfo)
  case unverified
}

/// What the App Store recorded about the original download, for `upgradeFromPaid`.
public enum OriginalPurchase: Sendable, Equatable {
  case production(originalAppVersion: String)
  /// Sandbox or Xcode, where `originalAppVersion` reads "1.0" or a build number.
  case notProduction
  /// Unverified, or the lookup failed.
  case inconclusive
}

/// Every call `ProStore` makes to the App Store. `.live` is StoreKit; a test builds one
/// from closures.
public struct StoreClient: Sendable {
  public var products: @Sendable ([String]) async throws -> [ProductInfo]
  /// Verified transactions only.
  public var currentEntitlements: @Sendable () async -> [TransactionInfo]
  public var unfinished: @Sendable () async -> [TransactionUpdate]
  public var updates: @Sendable () -> AsyncStream<TransactionUpdate>
  public var sync: @Sendable () async throws -> Void
  public var originalPurchase: @Sendable () async -> OriginalPurchase
  /// True for `.live` alone, which a test host must never start.
  let isLive: Bool

  public init(
    products: @escaping @Sendable ([String]) async throws -> [ProductInfo],
    currentEntitlements: @escaping @Sendable () async -> [TransactionInfo],
    unfinished: @escaping @Sendable () async -> [TransactionUpdate],
    updates: @escaping @Sendable () -> AsyncStream<TransactionUpdate>,
    sync: @escaping @Sendable () async throws -> Void,
    originalPurchase: @escaping @Sendable () async -> OriginalPurchase
  ) {
    self.init(
      isLive: false, products: products, currentEntitlements: currentEntitlements,
      unfinished: unfinished, updates: updates, sync: sync, originalPurchase: originalPurchase)
  }

  init(
    isLive: Bool,
    products: @escaping @Sendable ([String]) async throws -> [ProductInfo],
    currentEntitlements: @escaping @Sendable () async -> [TransactionInfo],
    unfinished: @escaping @Sendable () async -> [TransactionUpdate],
    updates: @escaping @Sendable () -> AsyncStream<TransactionUpdate>,
    sync: @escaping @Sendable () async throws -> Void,
    originalPurchase: @escaping @Sendable () async -> OriginalPurchase
  ) {
    self.isLive = isLive
    self.products = products
    self.currentEntitlements = currentEntitlements
    self.unfinished = unfinished
    self.updates = updates
    self.sync = sync
    self.originalPurchase = originalPurchase
  }

  /// Whether a verified, unrevoked purchase of any of `productIDs` is current. Reads
  /// `currentEntitlements` rather than `latest(for:)`: a revoked Family Sharing grant can
  /// leave `latest(for:)` reporting revoked while the user owns their own purchase.
  public func isEntitled(to productIDs: Set<String>) async -> Bool {
    await currentEntitlements().contains { productIDs.contains($0.productID) && !$0.isRevoked }
  }
}
```

`Sources/SupportKitStore/StoreClient+Live.swift`:

```swift
import StoreKit

extension StoreClient {
  /// StoreKit 2.
  public static let live = StoreClient(
    isLive: true,
    products: { ids in try await Product.products(for: ids).map(ProductInfo.init(product:)) },
    currentEntitlements: {
      var verified: [TransactionInfo] = []
      for await result in Transaction.currentEntitlements {
        if case .verified(let transaction) = result { verified.append(TransactionInfo(transaction)) }
      }
      return verified
    },
    unfinished: {
      var updates: [TransactionUpdate] = []
      for await result in Transaction.unfinished { updates.append(TransactionUpdate(result)) }
      return updates
    },
    updates: {
      AsyncStream { continuation in
        let task = Task {
          for await result in Transaction.updates { continuation.yield(TransactionUpdate(result)) }
          continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
      }
    },
    sync: { try await AppStore.sync() },
    originalPurchase: {
      guard let result = try? await AppTransaction.shared, case .verified(let app) = result
      else { return .inconclusive }
      return app.environment == .production
        ? .production(originalAppVersion: app.originalAppVersion) : .notProduction
    })
}

extension ProductInfo {
  init(product: Product) {
    self.init(id: product.id, displayPrice: product.displayPrice) {
      switch try await product.purchase() {
      case .success(.verified(let transaction)): .verified(TransactionInfo(transaction))
      case .success(.unverified(_, let error)): .unverified(reason: error.localizedDescription)
      case .pending: .pending
      case .userCancelled: .cancelled
      @unknown default: .cancelled
      }
    }
  }
}

extension TransactionInfo {
  init(_ transaction: Transaction) {
    self.init(productID: transaction.productID, isRevoked: transaction.revocationDate != nil) {
      await transaction.finish()
    }
  }
}

extension TransactionUpdate {
  init(_ result: VerificationResult<Transaction>) {
    if case .verified(let transaction) = result {
      self = .verified(TransactionInfo(transaction))
    } else {
      self = .unverified
    }
  }
}
```

- [ ] **Step 6: Run to verify it passes**

Run: `swift test --filter "SupportKitStoreTests|CatalogDrift|CatalogResolution"`
Expected: 3 store tests pass; the catalog suites pass for `SupportKitStore` with an empty catalog. If the compiler flags the `switch` expression in `ProductInfo.init(product:)` (a `try await` inside a switch-expression subject is allowed; a branch that cannot be an expression is not), rewrite it as a `switch` statement with `return` in each case.

- [ ] **Step 7: Full suite and lint, then commit**

Run: `swift test 2>&1 | grep -E "Test run with|error:"` and `xcrun swift-format lint --strict --recursive Package.swift Sources Tests`
Expected: all pass, no lint output.

```bash
git add Package.swift Sources/SupportKitStore Tests/SupportKitStoreTests Tests/SupportKitLocalizationTests/CatalogScanner.swift
git commit -m "feat(SupportKitStore): add the product and its StoreKit seam, a client of closures over the store's own values, so the Pro lifecycle can be tested without StoreKit"
```

---

### Task 3: `ProStore`: modes, cache, entitlements and the listener

**Files:**
- Create: `Sources/SupportKitStore/ProStore.swift`
- Create: `Tests/SupportKitStoreTests/ProStoreSupport.swift`
- Create: `Tests/SupportKitStoreTests/ProStoreEntitlementTests.swift`

**Interfaces:**
- Consumes: `StoreClient`, `TransactionInfo`, `TransactionUpdate`, `OriginalPurchase`, `isEntitled(to:)` (Task 2); `ProPurchaseState` (Task 1).
- Produces: `public final class ProStore` (`@Observable @MainActor`) with `Mode`, `UnlockReason`, `Configuration`; `public init(_:client:)`; internal `init(_:client:isTestHost:)`; published `isPro`, `displayPrice`, `isLoadingProduct`, `unlockReason`, `isWorking`, `isPurchasePending`, `lastError`; internal `isEntitlementResolved`, `isProductAnswered`; `public var purchaseState: ProPurchaseState`; `public func start()`; internal `func refresh() async`, `func settled() async`; private `handle(_:)`, `grant()`, `apply(_:reason:)`, `entitles(_:)`; `public nonisolated static func hasEntitlement(_:) async -> Bool`; internal `nonisolated static func version(_:isAtMost:) -> Bool`. Task 4 adds the product load into `start()` and `settled()`; Task 5 adds `purchase()`, `restore()`, `clearError()`.

- [ ] **Step 1: Write the test support and the failing tests**

`Tests/SupportKitStoreTests/ProStoreSupport.swift`:

```swift
import Foundation

@testable import SupportKitStore

@MainActor
func makeStore(
  _ script: StoreScript, _ configure: (inout ProStore.Configuration) -> Void = { _ in }
) -> ProStore {
  var configuration = ProStore.Configuration(
    productID: "pro", defaults: UserDefaults(suiteName: "ProStoreTests.\(UUID())")!)
  configure(&configuration)
  return ProStore(configuration, client: script.client, isTestHost: false)
}

/// Collects `onChange` calls. A class, because an isolated closure cannot capture a `var`.
@MainActor
final class Recorder {
  var values: [Bool] = []
}

/// Polls until `condition` holds, for effects that arrive through the updates listener.
@MainActor
func eventually(_ condition: () -> Bool) async -> Bool {
  for _ in 0..<200 {
    if condition() { return true }
    try? await Task.sleep(for: .milliseconds(5))
  }
  return condition()
}
```

`Tests/SupportKitStoreTests/ProStoreEntitlementTests.swift`:

```swift
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
    #expect(await script.syncs == 0)
  }

  @Test("A test host with the live client starts nothing and settles locked")
  func testHostStaysIdle() {
    let store = ProStore(.init(productID: "pro"), client: .live, isTestHost: true)
    store.start()
    #expect(!store.isPro)
    #expect(store.purchaseState == .locked(price: nil))
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

  @Test("A cached unlock shows Unlocked before StoreKit answers")
  func cachedUnlockShowsAtOnce() {
    let defaults = UserDefaults(suiteName: "ProStoreTests.\(UUID())")!
    defaults.set(true, forKey: "pro.cache")
    let store = ProStore(
      .init(productID: "pro", cacheKey: "pro.cache", defaults: defaults),
      client: StoreScript().client, isTestHost: false)
    #expect(store.purchaseState == .unlocked)
  }

  @Test("A stale cached unlock is corrected once StoreKit answers")
  func aStaleCachedUnlockIsCorrected() async {
    let defaults = UserDefaults(suiteName: "ProStoreTests.\(UUID())")!
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
    let defaults = UserDefaults(suiteName: "ProStoreTests.\(UUID())")!
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
    let defaults = UserDefaults(suiteName: "ProStoreTests.\(UUID())")!
    defaults.set(true, forKey: "pro.cache")
    let store = ProStore(
      .init(productID: "pro", upgradeFromPaid: "1.2.2", cacheKey: "pro.cache", defaults: defaults),
      client: script.client, isTestHost: false)
    store.start()
    await store.settled()
    #expect(store.isPro)
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

  @Test("A slow read that began before a grant cannot undo it")
  func slowReadCannotUndoAGrant() async {
    let script = StoreScript()
    let gate = await script.gateEntitlements()
    let store = makeStore(script)
    store.start()
    script.updatesContinuation.yield(.verified(script.transaction("pro")))
    #expect(await eventually { store.isPro })
    gate.open()
    await store.settled()
    #expect(store.isPro)
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
    try? await Task.sleep(for: .milliseconds(50))
    #expect(store.isPro)
  }

  @Test("Updates for other products are finished, not granted")
  func otherProductsFinishedNotGranted() async {
    let script = StoreScript()
    let store = makeStore(script)
    store.start()
    await store.settled()
    script.updatesContinuation.yield(.verified(script.transaction("tip")))
    try? await Task.sleep(for: .milliseconds(50))
    #expect(!store.isPro)
    #expect(await script.finished == ["tip"])
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter ProStoreEntitlementTests`
Expected: build failure, `cannot find 'ProStore' in scope`.

- [ ] **Step 3: Write the store**

`Sources/SupportKitStore/ProStore.swift`:

```swift
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
  }

  /// Waits for the work `start()` began. For tests.
  func settled() async {
    await firstRead?.value
  }

  private func readFirst() async {
    for update in await client.unfinished() { await handle(update) }
    await refresh()
    if !Task.isCancelled { isEntitlementResolved = true }
  }

  /// Re-reads what the App Store says. Discarded when a grant landed meanwhile, and when the
  /// task was cancelled.
  func refresh() async {
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
    guard !Task.isCancelled, grants == generation else { return }
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
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter ProStoreEntitlementTests`
Expected: all pass. `cachedLockStaysUnknown` and `unknownBeforeStart` rely on `isProductAnswered` never being set in this task; Task 4 keeps them true because they never call `start()`.

- [ ] **Step 5: Full suite and lint, then commit**

Run: `swift test 2>&1 | grep -E "Test run with|error:"` and `xcrun swift-format lint --strict --recursive Package.swift Sources Tests`
Expected: all pass, no lint output.

```bash
git add Sources/SupportKitStore/ProStore.swift Tests/SupportKitStoreTests/ProStoreSupport.swift Tests/SupportKitStoreTests/ProStoreEntitlementTests.swift
git commit -m "feat(SupportKitStore): add ProStore's entitlement half: modes, the cache, the first read it owns, the listener, and the upgrade check for apps that were once paid"
```

---

### Task 4: `ProStore`: loading the product, and retrying it

**Files:**
- Modify: `Sources/SupportKitStore/ProStore.swift` (`start()`, `settled()`, new `ensureProduct()`, `isProductUnavailable`, `loadProduct()`, `finishLoading(_:)`)
- Create: `Tests/SupportKitStoreTests/ProStoreProductTests.swift`

**Interfaces:**
- Consumes: Task 3's `ProStore`, `runsStoreKit`, `product`, `productLoad`; Task 2's `ProductInfo`.
- Produces: `public func ensureProduct() async`; `public var isProductUnavailable: Bool`; `start()` now also loads a missing product.

- [ ] **Step 1: Write the failing tests**

`Tests/SupportKitStoreTests/ProStoreProductTests.swift`:

```swift
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
    gate.open()
    await store.settled()
    #expect(store.purchaseState == .locked(price: nil))
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

  @Test("Forced mode is never Unavailable")
  func forcedIsNeverUnavailable() {
    let store = makeStore(StoreScript()) { $0.mode = .forced(isPro: false, price: nil) }
    #expect(!store.isProductUnavailable)
  }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter ProStoreProductTests`
Expected: build failure, `value of type 'ProStore' has no member 'ensureProduct'` and `'isProductUnavailable'`.

- [ ] **Step 3: Add the product load**

In `Sources/SupportKitStore/ProStore.swift`, in `start()`, after the `if listener == nil { … }` block, add:

```swift
    // The retry: a lookup that failed once (offline at launch, a storefront the product is
    // not sold in) would otherwise leave Unlock dead until the next launch.
    if product == nil, productLoad == nil { loadProduct() }
```

Replace `settled()` with:

```swift
  /// Waits for the work `start()` began. For tests.
  func settled() async {
    await firstRead?.value
    await productLoad?.value
  }
```

Add after `purchaseState`:

```swift
  /// The store answered and gave no product, and is not asking again right now. The views
  /// offer Try Again.
  public var isProductUnavailable: Bool {
    runsStoreKit && isProductAnswered && !isLoadingProduct && displayPrice == nil
  }
```

Add a `// MARK: - Product` section before `// MARK: - Without a store`:

```swift
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
    productLoad = Task { [weak self] in
      var answer: ProductInfo?
      do {
        answer = try await client.products([id]).first
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

  /// `isProductAnswered` is never reset, so a retry that fails keeps `.locked(price: nil)`
  /// rather than going back to `.unknown`, which would take every PRO badge away while it runs.
  private func finishLoading(_ answer: ProductInfo?) {
    product = answer
    displayPrice = answer?.displayPrice
    isProductAnswered = true
    isLoadingProduct = false
    productLoad = nil
  }
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter "ProStoreProductTests|ProStoreEntitlementTests"`
Expected: all pass.

- [ ] **Step 5: Full suite and lint, then commit**

Run: `swift test 2>&1 | grep -E "Test run with|error:"` and `xcrun swift-format lint --strict --recursive Package.swift Sources Tests`
Expected: all pass, no lint output.

```bash
git add Sources/SupportKitStore/ProStore.swift Tests/SupportKitStoreTests/ProStoreProductTests.swift
git commit -m "feat(SupportKitStore): load the product on every start that finds it missing, and let a caller wait for a load in flight, so a failed launch lookup no longer leaves Unlock dead until a relaunch"
```

---

### Task 5: `ProStore`: purchase, restore and errors

**Files:**
- Modify: `Sources/SupportKitStore/ProStore.swift` (new `// MARK: - Purchase` section)
- Modify: `Sources/SupportKitStore/Resources/Localizable.xcstrings`
- Create: `Tests/SupportKitStoreTests/ProStorePurchaseTests.swift`

**Interfaces:**
- Consumes: Task 3's `grant()`, `refresh()`, `handle(_:)` (make it `func handle` internal if Swift needs it from the extension; keep it in the class body to avoid that), `entitles(_:)`; Task 4's `ensureProduct()`, `product`.
- Produces: `public func purchase() async`, `public func restore() async`, `public func clearError()`.

- [ ] **Step 1: Write the failing tests**

`Tests/SupportKitStoreTests/ProStorePurchaseTests.swift`:

```swift
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
    let store = await readyStore(script, script.product(outcome: .unverified(reason: "Bad receipt")))
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter ProStorePurchaseTests`
Expected: build failure, `value of type 'ProStore' has no member 'purchase'` (and `restore`, `clearError`).

- [ ] **Step 3: Add purchase and restore**

In `Sources/SupportKitStore/ProStore.swift`, add before `// MARK: - Without a store`:

```swift
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
```

- [ ] **Step 4: Add the strings**

In `Sources/SupportKitStore/Resources/Localizable.xcstrings`, replace the empty `"strings"` object with:

```json
  "strings" : {
    "No previous purchase was found on this Apple Account." : {
      "extractionState" : "manual",
      "generatesSymbol" : false,
      "localizations" : {
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Aucun achat précédent n’a été trouvé sur ce compte Apple."
          }
        }
      }
    },
    "The App Store did not return the purchase. Try again in a moment." : {
      "extractionState" : "manual",
      "generatesSymbol" : false,
      "localizations" : {
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "L’App Store n’a pas renvoyé l’achat. Réessayez dans un instant."
          }
        }
      }
    },
    "The purchase could not be verified: %@" : {
      "extractionState" : "manual",
      "generatesSymbol" : false,
      "localizations" : {
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "L’achat n’a pas pu être vérifié : %@"
          }
        }
      }
    }
  },
```

Before writing the French colon, check how the Settings catalog spaces a French colon (`grep -n ' :' Sources/SupportKitSettings/Resources/Localizable.xcstrings`) and match it (a regular space, a no-break space, or a narrow no-break space).

- [ ] **Step 5: Run to verify it passes**

Run: `swift test --filter "ProStore|CatalogDrift|CatalogResolution"`
Expected: all pass, including the drift suite for `SupportKitStore` (3 call sites, 3 entries).

- [ ] **Step 6: Full suite and lint, then commit**

Run: `swift test 2>&1 | grep -E "Test run with|error:"` and `xcrun swift-format lint --strict --recursive Package.swift Sources Tests`
Expected: all pass, no lint output.

```bash
git add Sources/SupportKitStore Tests/SupportKitStoreTests/ProStorePurchaseTests.swift
git commit -m "feat(SupportKitStore): buy and restore, with pending as a note rather than an error, an unverified purchase left unfinished, and a restore that says when it found nothing"
```

---

### Task 6: Spike: StoreKitTest under `swift test`

The spec leaves open whether `SKTestSession` runs in a SwiftPM test target with no host app. This task finds out. Either outcome completes the task.

**Files:**
- Create: `Tests/SupportKitStoreTests/Fixtures/Pro.storekit`
- Create: `Tests/SupportKitStoreTests/ProStoreStoreKitTests.swift`
- Modify: `Package.swift` (the `SupportKitStoreTests` target gains `resources: [.copy("Fixtures")]`)

**Interfaces:**
- Consumes: the public `ProStore` API from Tasks 3-5.
- Produces: nothing other tasks use.

- [ ] **Step 1: Add the fixture**

`Tests/SupportKitStoreTests/Fixtures/Pro.storekit`: copy `/Users/olivier/Projects/apps/kv-explorer/apps/apple/KVExplorer.storekit` verbatim, then change only the product: `"productID": "io.mgcrea.SupportKitStore.pro"`, `"referenceName": "Pro"`, `"displayName": "Pro"`, and `"displayPrice": "5.99"` (already). Keep every other field, including `settings` and `"_storefront": "USA"`.

In `Package.swift`:

```swift
    .testTarget(
      name: "SupportKitStoreTests",
      dependencies: ["SupportKitStore"],
      resources: [.copy("Fixtures")]
    ),
```

- [ ] **Step 2: Write the StoreKit tests**

`Tests/SupportKitStoreTests/ProStoreStoreKitTests.swift`:

```swift
import Foundation
import StoreKitTest
import SupportKit
import SupportKitStore
import Testing

/// The live client against a StoreKit configuration. Serialized: `SKTestSession` is
/// process-wide.
@Suite("Pro store against StoreKitTest", .serialized)
@MainActor
struct ProStoreStoreKitTests {
  static let productID = "io.mgcrea.SupportKitStore.pro"

  func session() throws -> SKTestSession {
    let url = try #require(
      Bundle.module.url(forResource: "Pro", withExtension: "storekit", subdirectory: "Fixtures"))
    let session = try SKTestSession(contentsOf: url)
    session.resetToDefaultState()
    session.clearTransactions()
    session.disableDialogs = true
    return session
  }

  @Test("Loads the price, buys, and a fresh store finds the purchase")
  func buysAndFindsItAgain() async throws {
    let session = try session()
    let store = ProStore(.init(productID: Self.productID))
    store.start()
    await store.ensureProduct()
    #expect(store.displayPrice != nil)
    await store.purchase()
    #expect(store.isPro)

    let fresh = ProStore(.init(productID: Self.productID))
    fresh.start()
    var found = false
    for _ in 0..<100 where !found {
      try await Task.sleep(for: .milliseconds(50))
      found = fresh.isPro
    }
    #expect(found)
    _ = session
  }

  @Test("Ask to Buy waits without failing")
  func askToBuyIsPending() async throws {
    let session = try session()
    session.askToBuyEnabled = true
    let store = ProStore(.init(productID: Self.productID))
    store.start()
    await store.purchase()
    #expect(store.isPurchasePending)
    #expect(store.lastError == nil)
    #expect(!store.isPro)
  }
}
```

- [ ] **Step 3: Run the spike**

Run: `swift test --filter ProStoreStoreKitTests 2>&1 | tail -30`

- If both tests pass: keep them. The suite lives in the kit.
- If they fail because StoreKitTest cannot run without a host app (a `SKTestSession` init error, products never loading with `displayPrice == nil`, or an entitlement error): delete `ProStoreStoreKitTests.swift` and `Fixtures/`, revert the `resources:` line in `Package.swift`, and record the ruling: "StoreKitTest does not run under `swift test`; the StoreKit suite moves to the KVExplorer adoption plan, against KVExplorer's `.storekit`."
- If they fail for any other reason, that is a store bug: debug it with superpowers:systematic-debugging before deciding.

- [ ] **Step 4: Full suite and lint, then commit (only if the tests were kept)**

Run: `swift test 2>&1 | grep -E "Test run with|error:"` and `xcrun swift-format lint --strict --recursive Package.swift Sources Tests`
Expected: all pass, no lint output.

```bash
git add Package.swift Tests/SupportKitStoreTests/Fixtures Tests/SupportKitStoreTests/ProStoreStoreKitTests.swift
git commit -m "test(SupportKitStore): buy, find again and Ask to Buy against a StoreKit configuration with the live client"
```

---

### Task 7: Try Again and the pending note in the sheet and the pane

**Files:**
- Modify: `Sources/SupportKitSettings/ProUpgradeSheet.swift` (`Action`, `action(state:isWorking:)`, stored properties, `init`, `body`, `unlockButton`)
- Modify: `Sources/SupportKitSettings/ProSettingsPane.swift` (stored properties, both `init`s, `body`, `actionButton`, `statusDetail`, new `showsTryAgain(state:hasRetry:)`)
- Modify: `Sources/SupportKitSettings/Resources/Localizable.xcstrings`
- Modify: `Tests/SupportKitSettingsTests/ProUpgradeSheetTests.swift`
- Create: `Tests/SupportKitSettingsTests/ProSettingsPaneRetryTests.swift`

**Interfaces:**
- Consumes: `ProPurchaseState` (Task 1).
- Produces: `ProUpgradeSheet.Action.retry`; `ProUpgradeSheet.action(state:isWorking:canRetry:)` with `canRetry: Bool = false`; `ProUpgradeSheet.init(…, errorMessage:, isPending: Bool = false, installedVersion:, purchase:, retry: (() -> Void)? = nil, restore:)`; `ProSettingsPane.init(…, errorMessage:, isPending: Bool = false, unlockedDetail:, featuresFooter:, installedVersion:, purchase:, retry: (() -> Void)? = nil, restore:, notes:)` and the same on the `Notes == EmptyView` init; `nonisolated static func showsTryAgain(state: ProPurchaseState, hasRetry: Bool) -> Bool` on `ProSettingsPane`.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/SupportKitSettingsTests/ProUpgradeSheetTests.swift`, inside the suite:

```swift
  @Test("No product, and the app can ask again: Try Again")
  func retryWhenTheAppCanRetry() {
    #expect(
      ProUpgradeSheet.action(state: .locked(price: nil), isWorking: false, canRetry: true)
        == .retry)
  }

  @Test("Try Again only when there is no price")
  func noRetryWithAPrice() {
    #expect(
      ProUpgradeSheet.action(state: .locked(price: "$9.99"), isWorking: false, canRetry: true)
        == .buy(price: "$9.99"))
  }

  @Test("Asking again shows progress, not a second Try Again")
  func retryInFlightShowsProgress() {
    #expect(
      ProUpgradeSheet.action(state: .locked(price: nil), isWorking: true, canRetry: true)
        == .working)
  }
```

`Tests/SupportKitSettingsTests/ProSettingsPaneRetryTests.swift`:

```swift
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
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter "ProUpgradeSheetTests|ProSettingsPaneRetryTests"`
Expected: build failure, `extra argument 'canRetry' in call` and `type 'ProSettingsPane<EmptyView>' has no member 'showsTryAgain'`.

- [ ] **Step 3: The sheet**

In `Sources/SupportKitSettings/ProUpgradeSheet.swift`:

Add to `Action`, after `case unavailable`:

```swift
    /// The product did not load and the app can ask again.
    case retry
```

Replace `action(state:isWorking:)` with:

```swift
  /// `nonisolated` so tests and callers off the main actor can ask without hopping to it.
  public nonisolated static func action(
    state: ProPurchaseState, isWorking: Bool, canRetry: Bool = false
  ) -> Action {
    if isWorking { return .working }
    switch state {
    case .unknown: return .working
    case .locked(let price?): return .buy(price: price)
    case .locked(nil): return canRetry ? .retry : .unavailable
    case .unlocked: return .owned
    }
  }
```

Add stored properties after `private let errorMessage: String?`:

```swift
  private let isPending: Bool
  private let retry: (() -> Void)?
```

In `init`, add the parameters `isPending: Bool = false,` after `errorMessage: String? = nil,` and `retry: (() -> Void)? = nil,` between `purchase:` and `restore:`, document them in the doc comment (`isPending`: "a purchase waiting for Ask to Buy or a deferred payment; draws the kit's note"; `retry`: "asks the store again, `{ store.start() }`; with it, a product that did not load gets Try Again and is asked for once as the sheet appears"), and assign `self.isPending = isPending` and `self.retry = retry`.

Add a computed property:

```swift
  private var currentAction: Action {
    Self.action(state: state, isWorking: isWorking, canRetry: retry != nil)
  }
```

In `body`, after the `if let errorMessage { … }` block, add:

```swift
      if isPending {
        Text(localized("Waiting for approval. The purchase completes as soon as it is approved."))
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      if currentAction == .retry {
        Text(localized("The App Store could not be reached."))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
```

and, after `.accessibilityIdentifier("pro.upgrade")`:

```swift
    // Once, as it appears: the price someone came for, without a tap on Try Again.
    .task { if currentAction == .retry { retry?() } }
```

In `unlockButton`, change `switch Self.action(state: state, isWorking: isWorking) {` to `switch currentAction {` and add after `case .unavailable:`'s body:

```swift
    case .retry:
      Button(localized("Try Again")) { retry?() }
        .help(localized("The App Store could not be reached."))
```

- [ ] **Step 4: The pane**

In `Sources/SupportKitSettings/ProSettingsPane.swift`:

Add stored properties after `private let errorMessage: String?`:

```swift
  private let isPending: Bool
  private let retry: (() -> Void)?
```

In the generic `init`, add `isPending: Bool = false,` after `errorMessage: String? = nil,` and `retry: (() -> Void)? = nil,` between `purchase:` and `restore:`, with doc lines as for the sheet, and assign both. In the `extension ProSettingsPane where Notes == EmptyView` init, add the same two parameters in the same places and pass them through: `isPending: isPending,` and `retry: retry,`.

Add:

```swift
  /// Whether the action is Try Again: no product, and the app passed a way to ask again.
  nonisolated static func showsTryAgain(state: ProPurchaseState, hasRetry: Bool) -> Bool {
    hasRetry && state == .locked(price: nil)
  }
```

In `body`, in the first `Section`, after `notes`:

```swift
        if isPending {
          Text(localized("Waiting for approval. The purchase completes as soon as it is approved."))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
```

and after `.accessibilityIdentifier("settings.pro.content")`:

```swift
    .task { if Self.showsTryAgain(state: state, hasRetry: retry != nil) { retry?() } }
```

In `actionButton`, replace the `case .locked(nil):` branch with:

```swift
    case .locked(nil):
      if let retry {
        Button(localized("Try Again"), action: retry)
          .disabled(isWorking)
          .help(localized("The App Store could not be reached."))
      } else {
        Button(localized("Unavailable")) {}
          .disabled(true)
          .help(localized("The App Store could not be reached."))
      }
```

In `statusDetail`, before `case .locked:`, add:

```swift
    case .locked(nil) where retry != nil: localized("The App Store could not be reached.")
```

- [ ] **Step 5: The strings**

Add two entries to `Sources/SupportKitSettings/Resources/Localizable.xcstrings`, in key order:

```json
    "Try Again" : {
      "extractionState" : "manual",
      "generatesSymbol" : false,
      "localizations" : {
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Réessayer"
          }
        }
      }
    },
```

```json
    "Waiting for approval. The purchase completes as soon as it is approved." : {
      "extractionState" : "manual",
      "generatesSymbol" : false,
      "localizations" : {
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "En attente d’approbation. L’achat se termine dès qu’il est approuvé."
          }
        }
      }
    },
```

- [ ] **Step 6: Run to verify it passes**

Run: `swift test --filter "ProUpgradeSheetTests|ProSettingsPaneRetryTests|CatalogDrift|CatalogResolution|ProBadge"`
Expected: all pass, including every pre-existing sheet test (`.unavailable` with no retry is unchanged).

- [ ] **Step 7: Full suite and lint, then commit**

Run: `swift test 2>&1 | grep -E "Test run with|error:"` and `xcrun swift-format lint --strict --recursive Package.swift Sources Tests`
Expected: all pass, no lint output.

```bash
git add Sources/SupportKitSettings Tests/SupportKitSettingsTests
git commit -m "feat(SupportKitSettings): offer Try Again where the product did not load, asking once as the sheet or pane appears, and draw a pending purchase as the kit's note rather than each app's"
```

---

### Task 8: Documentation and the 1.21.0 tag

**Files:**
- Modify: `README.md` (a `SupportKitStore` section beside the existing products, and the products list)

**Interfaces:**
- Consumes: the public API of Tasks 1-7.
- Produces: tag `1.21.0` (local).

- [ ] **Step 1: Document the product**

In `README.md`, wherever the products are listed, add `SupportKitStore`, and add a section:

````markdown
## SupportKitStore

The Pro unlock: one non-consumable, what the App Store says about it, and buying and
restoring it. Every StoreKit app in the fleet sells exactly that, so the lifecycle lives here
once.

```swift
import SupportKitStore

let pro = ProStore(.init(
  productID: "io.mgcrea.KVExplorer.pro",
  mode: ScreenshotMode.isActive ? .forced(isPro: true, price: nil) : .live,
  cacheKey: "kv-explorer.pro-unlocked"))
pro.start()   // at launch, and from every view that wants a price
```

It owns the first entitlement read, retries a product that did not load each time `start()`
is called, grants straight from a verified purchase, and never lets a read that began before
a grant undo it. `purchaseState` feeds `ProSettingsPane`, `ProUpgradeSheet` and `ProBadge`;
pass `retry: { pro.start() }` and `isPending: pro.isPurchasePending` to them.

- `alsoEntitling`: retired product ids that still grant Pro.
- `upgradeFromPaid`: buyers of the paid app at or before this version get Pro, in
  production only. It is compared with `AppTransaction.originalAppVersion`, which is the
  marketing version on macOS and the **build number** on iOS.
- `.forced(isPro:price:)`: screenshots, demo mode, and an app not selling yet. StoreKit is
  never touched.
- A test host with the live client starts nothing.
- `ProStore.hasEntitlement(_:)`: for App Intents and share extensions, with no store.

The paywall flag, the gate and partial grandfathering stay in the app, built on `isPro`.
````

- [ ] **Step 2: Full verification**

Run: `swift build 2>&1 | tail -3`, `swift test 2>&1 | grep -E "Test run with|error:|failed"`, `xcrun swift-format lint --strict --recursive Package.swift Sources Tests`
Expected: build succeeds, every suite passes, no lint output.

- [ ] **Step 3: Commit and tag locally**

```bash
git add README.md
git commit -m "docs: document SupportKitStore, the Pro store the fleet's StoreKit apps share"
git tag -a 1.21.0 -m "SupportKitStore, and Try Again in the Pro sheet and pane"
```

Do not push the branch or the tag; landing is the user's call.
