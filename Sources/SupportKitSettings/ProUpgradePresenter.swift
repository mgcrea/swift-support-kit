import SwiftUI

extension View {
  /// Presents the upgrade sheet for `item`, and once it closes calls `onUnlock` with the
  /// request if Pro is then unlocked: bought, restored, or found to be owned already. The
  /// thing that was asked for before paying then simply happens: the piece opens, the piano
  /// is chosen.
  ///
  /// Generalised from Pochette's `UpgradeSheetPresenter`. `isUnlocked` is read when the sheet
  /// closes, not when it opens, so a purchase made while it was up counts.
  public func proUpgradeSheet<Request: Identifiable, Sheet: View>(
    item: Binding<Request?>,
    isUnlocked: @escaping () -> Bool,
    onUnlock: @escaping (Request) -> Void,
    @ViewBuilder content: @escaping (Request) -> Sheet
  ) -> some View {
    modifier(
      ProUpgradePresenter(item: item, isUnlocked: isUnlocked, onUnlock: onUnlock, sheet: content))
  }
}

struct ProUpgradePresenter<Request: Identifiable, Sheet: View>: ViewModifier {
  @Binding var item: Request?
  let isUnlocked: () -> Bool
  let onUnlock: (Request) -> Void
  let sheet: (Request) -> Sheet

  /// The request, kept past the binding going nil so the dismissal still has it.
  @State private var held: Request?

  /// What to finish when the sheet closes: the held request if Pro is unlocked by then.
  nonisolated static func unlocked(_ held: Request?, isUnlocked: Bool) -> Request? {
    isUnlocked ? held : nil
  }

  func body(content: Content) -> some View {
    content
      .onChange(of: item?.id) { if let item { held = item } }
      .sheet(item: $item) {
        if let request = Self.unlocked(held, isUnlocked: isUnlocked()) { onUnlock(request) }
        held = nil
      } content: { request in
        sheet(request)
      }
  }
}
