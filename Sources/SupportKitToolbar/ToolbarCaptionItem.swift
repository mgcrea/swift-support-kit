#if os(macOS)
  import SwiftUI

  /// A toolbar item for a caption control, with the toolbar's shared glass
  /// background hidden.
  ///
  /// `ToolbarCaptionButton` and `ToolbarCaptionMenu` draw their own capsule,
  /// sized by their label. Inside the shared background they are sized by the
  /// toolbar instead, and on macOS 27 that is one control row tall — the clipped
  /// second line this module exists to fix.
  ///
  /// Hiding the shared background is a modifier on the toolbar item, not on the
  /// view inside it, so no control can apply it to itself. Every call site would
  /// have to remember it, and the one that forgot would look correct on 26 and
  /// ship clipped on 27. This wrapper is how it cannot be forgotten.
  ///
  /// ```swift
  /// .toolbar {
  ///   ToolbarCaptionItem(placement: .primaryAction) {
  ///     ToolbarCaptionButton(…) { … }
  ///   }
  /// }
  /// ```
  public struct ToolbarCaptionItem<Content: View>: ToolbarContent {
    private let placement: ToolbarItemPlacement
    private let content: Content

    public init(
      placement: ToolbarItemPlacement = .automatic,
      @ViewBuilder content: () -> Content
    ) {
      self.placement = placement
      self.content = content()
    }

    public var body: some ToolbarContent {
      ToolbarItem(placement: placement) {
        content
      }
      .sharedBackgroundVisibility(.hidden)
    }
  }
#endif
