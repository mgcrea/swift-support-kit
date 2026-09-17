#if os(macOS)
  import AppKit
  import SwiftUI

  /// A row in the panel's body that goes somewhere.
  ///
  /// Lifted from armada, where the first clickable rows shipped looking dead.
  ///
  /// **Two affordances rather than one, because `pointerStyle(.link)` does not
  /// show over a row in a `MenuBarExtra` panel.** The cursor stays an arrow, so
  /// the only feedback those rows gave was the `.plain` press flash, after the
  /// click. The hover fill is what a menu row is expected to have anyway, and
  /// unlike a pointer style it is visible before committing. The pointer stays
  /// because it costs nothing where it does work.
  ///
  /// `contentShape` is the other half: `Spacer` does not hit-test, so without it
  /// most of a row's width is dead to both the click and the hover.
  ///
  /// **The accessory sits beside the button, not inside its label.** A button
  /// nested in another button's label hands its click to the outer one on macOS,
  /// so a trailing control has to be a sibling, and the hover fill goes on the
  /// stack holding both so the row still lights as one piece when the pointer is
  /// over the accessory.
  ///
  /// `help` is the tooltip and the VoiceOver hint both. The label already reads
  /// as the row's name; what a tooltip adds is where the click goes, which is
  /// exactly what a hint is for.
  ///
  /// A row that opens one of the app's own windows should call
  /// `MenuBarPanelWindow.dismiss()` first. See there for why.
  @available(macOS 26, *)
  public struct MenuBarRow<Label: View, Accessory: View>: View {
    private let help: LocalizedStringKey
    private let action: () -> Void
    private let label: Label
    private let accessory: Accessory

    @State private var hovering = false

    public init(
      help: LocalizedStringKey,
      action: @escaping () -> Void,
      @ViewBuilder label: () -> Label,
      @ViewBuilder accessory: () -> Accessory
    ) {
      self.help = help
      self.action = action
      self.label = label()
      self.accessory = accessory()
    }

    public var body: some View {
      HStack(spacing: 4) {
        Button(action: action) {
          label.contentShape(.rect)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help(help)
        .accessibilityHint(Text(help))
        accessory
      }
      .onHover { hovering = $0 }
      .background(
        hovering ? AnyShapeStyle(.selection.opacity(0.25)) : AnyShapeStyle(.clear),
        in: .rect(cornerRadius: 4)
      )
    }
  }

  @available(macOS 26, *)
  extension MenuBarRow where Accessory == EmptyView {
    public init(
      help: LocalizedStringKey,
      action: @escaping () -> Void,
      @ViewBuilder label: () -> Label
    ) {
      self.init(help: help, action: action, label: label, accessory: { EmptyView() })
    }
  }

  /// Closing the `MenuBarExtra` panel from inside it.
  ///
  /// **Needed because the panel closes itself only when the app resigns active.**
  /// Two clicks never make that happen, and both leave the panel hanging:
  ///
  /// - Opening one of the app's own windows. The app stays active, so the panel
  ///   stays open over the window it just opened.
  /// - Focusing another app that is *already* frontmost. Nothing changes, nothing
  ///   resigns, and the click looks like it did nothing, which is how armada had
  ///   it reported.
  ///
  /// **Call it before opening the window, not after.** The panel is found as the
  /// key window that cannot become main. Once the app's own window is key, that
  /// window is what answers, and this correctly refuses to close it, so the
  /// panel stays open.
  ///
  /// Named for the window rather than hung off `MenuBarPanel`, which is generic
  /// over its content and would need its type parameters spelled out at every
  /// call site to reach a static.
  @MainActor
  public enum MenuBarPanelWindow {
    public static func dismiss() {
      let panel =
        NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible && !$0.canBecomeMain }
      guard let panel, !panel.canBecomeMain else { return }
      panel.close()
    }
  }
#endif
