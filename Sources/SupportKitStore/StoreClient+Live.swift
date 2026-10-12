import StoreKit

extension StoreClient {
  /// StoreKit 2. Idle under a test host, so a hosted test never reads the machine's
  /// purchases; see `ProStore`.
  public static let live = storeKit(isLive: true)

  /// StoreKit 2 without the test-host rule, for a hosted suite that drives it through an
  /// `SKTestSession`. `.live` there would start nothing.
  public static let storeKitTesting = storeKit(isLive: false)

  private static func storeKit(isLive: Bool) -> StoreClient {
    StoreClient(
      isLive: isLive,
      products: { ids in try await Product.products(for: ids).map(ProductInfo.init(product:)) },
      currentEntitlements: {
        var verified: [TransactionInfo] = []
        for await result in Transaction.currentEntitlements {
          if case .verified(let transaction) = result {
            verified.append(TransactionInfo(transaction))
          }
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
            for await result in Transaction.updates {
              continuation.yield(TransactionUpdate(result))
            }
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
