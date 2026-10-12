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
  private(set) var entitlementRequests = 0
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
  /// What the live client throws when the person dismisses the sign-in prompt.
  func cancelSync() { syncError = CancellationError() }

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

  nonisolated func failingProduct(_ error: any Error = Unreachable()) -> ProductInfo {
    ProductInfo(id: "pro", displayPrice: "$5.99") {
      await self.recordPurchase()
      throw error
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

  /// A gated read answers what was true when it was asked, like a read that stalled after
  /// StoreKit had already looked.
  private func answerEntitlements() async -> [TransactionInfo] {
    entitlementRequests += 1
    let answer = entitlements
    if let gate = entitlementGate {
      entitlementGate = nil
      await gate.wait()
    }
    return answer
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
