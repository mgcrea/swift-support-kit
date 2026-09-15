#if os(macOS)
  import SwiftUI

  /// A toolbar control that shows a `ToolbarCaptionLabel` and opens a popover.
  ///
  /// A popover rather than a menu when the choice needs more than a name. An
  /// `NSMenu` row has nowhere to put a model's one-line summary or its download
  /// size, and a slider inside a menu dismisses it on the first drag. When a list
  /// of names is enough, `ToolbarCaptionMenu` draws the same label.
  ///
  /// Place it in a `ToolbarCaptionItem`, or macOS 27 clips it; see
  /// `ToolbarCaptionLabel` for why.
  ///
  /// ```swift
  /// .toolbar {
  ///   ToolbarCaptionItem(placement: .primaryAction) {
  ///     ToolbarCaptionButton(
  ///       "Model",
  ///       value: selection.current?.displayName,
  ///       placeholder: "Choose a model",
  ///       systemImage: "cube.box",
  ///       isPresented: $isModelPickerPresented
  ///     ) {
  ///       ModelPicker()
  ///     }
  ///     .help("Choose the model the next run uses")
  ///   }
  /// }
  /// ```
  public struct ToolbarCaptionButton<Popover: View>: View {
    private let label: ToolbarCaptionLabel
    @Binding private var isPresented: Bool
    private let arrowEdge: Edge
    private let popover: Popover

    /// - Parameters:
    ///   - caption, value, placeholder, systemImage, showsIndicator: the label;
    ///     see `ToolbarCaptionLabel.init`.
    ///   - isPresented: a binding rather than internal state, so the app can open
    ///     the popover itself — a screenshot run staging the picker at launch, or
    ///     a menu command that reaches the same choice.
    ///   - arrowEdge: the edge the popover's arrow points from.
    ///   - popover: the popover's content. It sizes itself; the control imposes
    ///     no width.
    public init(
      _ caption: LocalizedStringKey,
      value: String?,
      placeholder: LocalizedStringKey,
      systemImage: String,
      showsIndicator: Bool = false,
      isPresented: Binding<Bool>,
      arrowEdge: Edge = .top,
      @ViewBuilder popover: () -> Popover
    ) {
      self.label = ToolbarCaptionLabel(
        caption,
        value: value,
        placeholder: placeholder,
        systemImage: systemImage,
        showsIndicator: showsIndicator
      )
      self._isPresented = isPresented
      self.arrowEdge = arrowEdge
      self.popover = popover()
    }

    public var body: some View {
      Button {
        isPresented.toggle()
      } label: {
        label
      }
      .buttonStyle(.plain)
      .toolbarCaptionCapsule()
      .popover(isPresented: $isPresented, arrowEdge: arrowEdge) {
        popover
      }
    }
  }
#endif
