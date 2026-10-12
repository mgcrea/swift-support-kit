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
