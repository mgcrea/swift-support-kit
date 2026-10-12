# Shared Pro store: `SupportKitStore`

Status: approved design, 12 October 2026. Implementation plan to follow.

## Why

Sixteen apps sell a Pro unlock, and each wrote its own StoreKit class. The UI half is
already shared (`ProSettingsPane`, `ProUpgradeSheet`, `ProBadge`, `ProPurchaseState`), the
StoreKit half is not, and the copies have drifted.

The drift has a measured cost. KVExplorer 1.0.0 (57) was rejected on the Mac under
guideline 2.1(b): App Review "cannot locate the In-App Purchases". The cause was a store
that asked StoreKit for its product once, at launch, and never again: when that request
failed or came back empty, the paywall showed no price and a disabled button until a
relaunch, and Settings ▸ Pro showed a disabled Unavailable. Ten of the sixteen stores have
that dead end (D1Explorer, R2Explorer, Pochette, Contour, Silhouette, Valise, DevPulse,
Balise, Cadence, BloatBuster). Five retry, each differently (Parcelle and Pupitre with an
in-flight guard, Calque, Filiation and Almanac without), and KVExplorer has an uncommitted
local fix. The kit's own sheet and pane bake the dead end in: with no product they draw a
disabled Unavailable and offer nothing.

## The survey

Every StoreKit app sells exactly one non-consumable, family-shareable except Balise's. No
app sells a subscription, a consumable or a second product; the licence-key apps (Bastion,
Cupertino, Armada) do not use StoreKit. So one store fits the whole fleet, and every real
difference between the sixteen is policy:

| Difference | Apps |
|---|---|
| Retired product ids that still grant Pro | Contour |
| Buyers of an earlier paid app get Pro (`AppTransaction.originalAppVersion`, production only) | D1Explorer, R2Explorer, DevPulse; planned in BloatBuster |
| Demo, screenshot and test modes that force Pro on or off, with a fixture price | most |
| Not selling yet: Pro for everyone, no StoreKit | Valise, BloatBuster |
| A callback when Pro changes | Almanac (iCloud Keychain move), Cadence (engine heal, sync) |
| An entitlement check with no window | Contour and Silhouette (App Intents), Valise (share extension) |
| A cached flag for a correct first frame | D1Explorer, R2Explorer, KVExplorer, DevPulse, Balise, BloatBuster |

Partial grandfathering stays in the app, layered over `isPro`: Silhouette's frozen
local-data check unlocks one gate, Balise's unlocks per POI source. So do the apps' access
values (`ProAccess` in Parcelle, Pupitre, Pochette and Cadence) and their gates, which are
per action, per feature or per data range and share no shape worth extracting.

The fleet already holds every piece of a correct store, never in one app. This design takes
them from where they are:

- `Transaction.currentEntitlements`, not `latest(for:)`: a revoked Family Sharing grant can
  leave `latest(for:)` reporting revoked while the user owns their own purchase (Almanac).
- Grant from the verified purchase transaction directly, since `currentEntitlements` lags
  behind a purchase (Contour, Filiation, Calque; measured under StoreKitTest).
- `.unknown` until both the entitlement and the product lookup have answered (Pupitre).
- A first read owned by the store, and a cancelled read that settles nothing (Calque).
- A grants counter, so a slow read cannot overwrite a purchase that landed meanwhile
  (Parcelle).
- Pending as its own state, never an error (D1Explorer, R2Explorer, Silhouette).
- Draining `Transaction.unfinished` at launch and after a restore (Cadence).
- Entitlements read before the product, so resolving Pro never waits on the network
  (DevPulse's ordering is the counter-example).
- `SKTestSession` purchase tests against a `.storekit` file (R2Explorer, Calque, Contour,
  Filiation, Valise, Almanac).

## Decisions

- **Scope:** the shared store, plus Try Again and a pending note in the kit's existing sheet
  and pane. Moving the ten apps that draw their own paywall sheet onto `ProUpgradeSheet` is
  optional per app and outside this project.
- **Shape:** one configured store (`ProStore`), not building blocks and not a protocol. The
  lifecycle (first read, retry, races, listener) is what drifted, so it exists once.
- **Pilot:** KVExplorer adopts first, and its App Review approval is what validates the kit
  before the other fifteen move.

## 1. Package placement

A new product, `SupportKitStore`: target `SupportKitStore`, depending on `SupportKit` and
linking StoreKit, with no SwiftUI. It follows the package's existing rule that a product
exists for what it links: an app that links the Help menu must not pull StoreKit in.

`ProPurchaseState` moves from `SupportKitSettings/ProSettingsPane.swift` into `SupportKit`,
which is Foundation-only, so the store can produce it without SwiftUI. Its cases and
semantics do not change.

Existing apps name the type after `import SupportKitSettings` alone, so the move must not
make them add an import. The plan's first check is whether a type declared in `SupportKit`
still resolves in an app that imports only `SupportKitSettings`, with
`MemberImportVisibility` on as it is in the fleet. If it does not, `SupportKitSettings`
adds `@_exported import SupportKit`; if that is unwanted, the fallback is to leave the enum
where it is and have `SupportKitSettings` offer an initializer from the store's own state
value.

`SupportKitStore` owns a `Resources/Localizable.xcstrings`, and every string it shows goes
through `localized(_:)` against `.module`, as the three UI targets do.
`SupportKitLocalizationTests` covers the new catalog.

## 2. Public surface

```swift
@Observable @MainActor
public final class ProStore {
  public init(_ configuration: Configuration, client: StoreClient = .live)

  public private(set) var isPro: Bool
  /// `.unlocked` when Pro; `.unknown` until the entitlement and the product lookup have
  /// both answered; otherwise `.locked(price:)`, where nil means the product did not load.
  public var purchaseState: ProPurchaseState { get }
  public private(set) var displayPrice: String?
  /// The store answered and gave no product. The UI offers Try Again.
  public var isProductUnavailable: Bool { get }
  public private(set) var isLoadingProduct: Bool
  public private(set) var unlockReason: UnlockReason?   // .purchased, .upgradedFromPaid, .forced
  public private(set) var isWorking: Bool               // purchase or restore in flight
  public private(set) var isPurchasePending: Bool       // Ask to Buy, deferred payment
  public private(set) var lastError: String?            // worded and localized by the kit

  public func start()
  public func ensureProduct() async
  public func purchase() async
  public func restore() async
  public func clearError()

  public nonisolated static func hasEntitlement(_ productIDs: Set<String>) async -> Bool
}

public struct Configuration: Sendable {
  public var productID: String
  public var alsoEntitling: Set<String> = []
  public var mode: Mode = .live
  public var upgradeFromPaid: String? = nil
  public var cacheKey: String? = nil
  public var defaults: UserDefaults = .standard
  public var onChange: (@MainActor @Sendable (Bool) -> Void)? = nil
}

public enum Mode: Sendable {
  case live
  /// No StoreKit, settled at once. Screenshots and demo mode pass a fixture price; "not
  /// selling yet" is `.forced(isPro: true, price: nil)`.
  case forced(isPro: Bool, price: String?)
}
```

`UserDefaults` is not `Sendable`; the plan settles how `Configuration` carries it (an
`nonisolated(unsafe)` stored property, or the configuration not being `Sendable` and only
ever built on the main actor). It is named here so it is not discovered late.

Not in the store, deliberately: `paywallPresented`, `gate(_:)`, the app's access value, and
partial grandfathering. Each app keeps its own and builds it on `isPro`.

## 3. Lifecycle

**Modes.** `.forced` never touches StoreKit and is settled on init: `isPro`, `displayPrice`
and `unlockReason = .forced` come from the mode, and `purchaseState` is `.unlocked` or
`.locked(price:)`, never `.unknown`. Under a test host (`XCTestConfigurationFilePath` set)
with the `.live` client, `.live` behaves as idle: it starts nothing and settles locked, so a
hosted test never reaches StoreKit or reads the machine's purchases. A test that injects a
client runs the live lifecycle against it.

**`start()`**, idempotent, called by the app at launch and by every view that wants a
price:

1. On the first call only, start the `Transaction.updates` listener, unconditionally and
   before anything that can fail. It is the only route for a purchase made on another
   device, a Family Sharing grant, an approved Ask to Buy, and a refund.
2. On the first call only, start the first read as a task the store owns, so a closing
   window cannot cancel it: drain `Transaction.unfinished`; read `currentEntitlements` for
   `productID ∪ alsoEntitling`, verified and unrevoked only; if still not Pro and
   `upgradeFromPaid` is set, run the upgrade check; then mark the entitlement resolved.
3. On every call, if there is no product and none is loading, load it. This is the retry.

**Upgrade check.** `AppTransaction.shared`, verified, in the production environment only
(sandbox and Xcode report `originalAppVersion` as "1.0" or a build number, which caused
D1Explorer's 1.2.0 rejection). Pro when `originalAppVersion` compares at or below the
cutoff, component by component. An unverified or failed lookup is inconclusive: it neither
grants nor revokes, and the cached value stands.

**Product load.** Sets `isLoadingProduct`, asks the client for `productID`, and records
that the lookup answered whatever the outcome. An empty answer is logged as an error naming
the product id (it is what a storefront the product is not sold in returns). A thrown error
is logged. Either way `displayPrice` stays nil and `isProductUnavailable` becomes true. A
later retry that fails keeps `.locked(price: nil)` rather than returning to `.unknown`, so
PRO badges do not vanish while it runs.

**`ensureProduct()`** returns at once when the product is loaded; awaits the load in flight
when there is one; otherwise starts one and awaits it.

**Races.** Every grant increments a counter. An entitlement read records the counter when it
starts and discards its result if the counter moved, so a read that began before a purchase
cannot revoke it. A read whose task was cancelled settles nothing.

**Purchase.** `ensureProduct()` first; with still no product, a localized "The App Store did
not return <product>. Try again in a moment." Otherwise purchase and handle the outcome:

- verified, unrevoked: grant (`unlockReason = .purchased`), then finish the transaction;
- unverified: an error, and the transaction is not finished;
- pending: `isPurchasePending = true`, not an error;
- cancelled: nothing;
- thrown: the error's description.

Any unlock clears `isPurchasePending` and `lastError`.

**Restore.** `AppStore.sync()`, drain `Transaction.unfinished`, re-read entitlements. Still
not Pro: "No previous purchase was found on this Apple Account."

**Listener.** For a verified transaction whose product is `productID ∪ alsoEntitling`: when
revoked, re-read every entitlement (a revoked Family Sharing grant must not remove the
person's own purchase), otherwise grant; then finish it. Other verified transactions are
finished. Unverified ones are skipped and not finished.

**Cache**, only when `cacheKey` is set. On init a cached `true` makes `isPro` true and
`purchaseState` `.unlocked` from the first frame, so nobody who paid is offered Buy; a
cached `false` leaves `.unknown` until the first read answers. Every resolution writes it.

**`onChange`** fires on every change of `isPro`, after the state is updated, never for the
initial value.

## 4. Kit UI (`SupportKitSettings`)

Additive; every new parameter defaults so that current callers compile and behave as
before.

- `ProUpgradeSheet` and `ProSettingsPane` gain `retry: (() -> Void)? = nil`. With a retry
  and `state == .locked(price: nil)`: the view calls it once when it appears, and the
  disabled Unavailable becomes an enabled **Try Again** with "The App Store could not be
  reached." beneath it. While `isWorking` the existing spinner shows. Without a retry,
  unchanged.
- Both gain `isPending: Bool = false`, drawing a neutral "Waiting for approval. Pro unlocks
  as soon as it is approved." in place of each app's own note or red error.
- `ProUpgradeSheet.Action` gains the retry distinction (`.unavailable(canRetry:)` or a
  separate case; the plan picks one and updates `action(state:isWorking:)` and its tests).
- New strings go in the module's catalog.

Apps with their own paywall sheet read `isProductUnavailable` and call `start()` to offer
the same Try Again.

## 5. Testing

**Seam.** `StoreClient` is a struct of closures: load products, current entitlements,
purchase, sync, unfinished, updates, app transaction. It traffics in the store's own values
(`ProductInfo` with a display price and a purchase action, `PurchaseOutcome`,
`TransactionInfo` with product id, revocation date and a finish action), never in StoreKit
types, which a test cannot construct. `.live` wraps StoreKit.

**Unit tests**, with a scripted client, one per rule in section 3: retry after a failed and
an empty load; `ensureProduct` awaiting a load in flight; the grants counter beating a slow
read; a cancelled read settling nothing; pending as a note; unverified not finished;
revocation re-reading; both cache rules; both forced modes; the test host idle;
`purchaseState` in each state; the upgrade check (production only, the comparison, the
inconclusive case); `onChange`. KVExplorer's three new purchase tests move here.

**StoreKit tests**: load, buy, restore, refund and Ask to Buy against a `.storekit` fixture,
`.serialized` with a fresh `SKTestSession` per test, polling entitlements as R2Explorer's
`settle()` does. Whether `SKTestSession` runs under `swift test` with no host app is not
known; the plan opens with a spike. If it runs, the suite lives in the kit. If it does not,
it lives in KVExplorer's test target against KVExplorer's real `.storekit` file.

**Kit UI tests**: `action(state:isWorking:)` gains the retry and pending cases, and
`SupportKitLocalizationTests` the new strings.

## 6. Rollout

1. **Kit 1.21.0**: `SupportKitStore`, the `ProPurchaseState` move, and the sheet and pane
   changes. Tagged and pushed.
2. **KVExplorer, the pilot**: `PurchaseManager` becomes a thin wrapper over `ProStore`
   (keeping `paywallPresented` and `gate(_:)`), with `cacheKey: "kv-explorer.pro-unlocked"`
   and `.forced` in screenshot mode. Settings ▸ Pro passes `retry` and `isPending`; its own
   `PaywallSheet` gains Try Again through `isProductUnavailable`. The uncommitted local fix
   of 12 October is superseded. A new build goes to App Review on the Mac with the reply to
   the 2.1(b) message; iOS when the user chooses. Approval is the gate for step 3.
3. **The other fifteen**, each its own small project with its own plan and release:
   D1Explorer and R2Explorer (same shape, plus `upgradeFromPaid` "1.1.0" and "1.2.2");
   then the apps with the dead end (Pochette, Contour, Silhouette, DevPulse, Balise,
   Cadence); then the ones that already retry (Parcelle, Pupitre, Calque, Filiation,
   Almanac); Valise and BloatBuster when they start selling.

## Out of scope

- Moving the ten app-drawn paywall sheets onto `ProUpgradeSheet`.
- A shared gate or paywall presenter.
- Subscriptions, consumables, several products: no app sells them.
- Partial or local grandfathering (Silhouette, Balise).
- The IAP's App Store Connect configuration (territories, review note): an App Store Connect
  task, done for KVExplorer separately.
