#if os(macOS)
  import SwiftUI

  /// A toolbar menu that shows a `ToolbarCaptionLabel`.
  ///
  /// For a choice a list of names can carry. When a row needs a summary, a size
  /// or a slider, use `ToolbarCaptionButton` and its popover instead.
  ///
  /// This replaces the workaround Contour used for its model and overlay menus:
  /// one `Text` holding an `AttributedString` with a newline, on the grounds
  /// that macOS flattened a stacked label inside a toolbar `Menu` down to its
  /// first `Text`. On macOS 27 it is the workaround that flattens — measured,
  /// it draws the caption and an ellipsis. A button-styled menu that draws its
  /// own glass keeps the stacked label whole, which is what this does.
  ///
  /// Place it in a `ToolbarCaptionItem`, or macOS 27 clips it; see
  /// `ToolbarCaptionLabel` for why.
  ///
  /// ```swift
  /// .toolbar {
  ///   ToolbarCaptionItem(placement: .primaryAction) {
  ///     ToolbarCaptionMenu(
  ///       "Overlay",
  ///       value: overlay.mode.name,
  ///       placeholder: "None",
  ///       systemImage: overlay.mode.systemImage
  ///     ) {
  ///       Picker("Overlay", selection: $overlay.mode) { … }
  ///         .pickerStyle(.inline)
  ///     }
  ///   }
  /// }
  /// ```
  public struct ToolbarCaptionMenu<Content: View>: View {
    private let label: ToolbarCaptionLabel
    private let content: Content

    /// - Parameters:
    ///   - caption, value, placeholder, systemImage, showsIndicator: the label;
    ///     see `ToolbarCaptionLabel.init`.
    ///   - content: the menu's items.
    public init(
      _ caption: LocalizedStringKey,
      value: String?,
      placeholder: LocalizedStringKey,
      systemImage: String,
      showsIndicator: Bool = false,
      @ViewBuilder content: () -> Content
    ) {
      self.label = ToolbarCaptionLabel(
        caption,
        value: value,
        placeholder: placeholder,
        systemImage: systemImage,
        showsIndicator: showsIndicator
      )
      self.content = content()
    }

    public var body: some View {
      Menu {
        content
      } label: {
        label
      }
      .menuStyle(.button)
      .buttonStyle(.plain)
      // The chevron would sit outside the label's padding and unbalance the
      // capsule, and a stacked caption already reads as a control that opens.
      .menuIndicator(.hidden)
      .toolbarCaptionCapsule()
    }
  }
#endif
