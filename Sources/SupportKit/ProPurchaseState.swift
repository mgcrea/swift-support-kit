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
