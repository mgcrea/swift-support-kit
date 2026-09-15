#if os(macOS)
  import SwiftUI

  /// An SF Symbol beside two stacked lines: a caption naming a setting, over
  /// the value it holds.
  ///
  /// Five toolbar controls in three apps drew this label by hand — Cadence's and
  /// Silhouette's model pickers, Silhouette's canvas and tune buttons, Contour's
  /// inference picker. Cadence's broke on macOS 27, and the other four are built
  /// the same way. The toolbar there wraps each item in a glass capsule one
  /// control row tall and clips whatever does not fit, so the value line lost
  /// its lower half and its last characters. The shipping binary was built
  /// against the 26.5 SDK and drew correctly on 26: nothing was relinked, the
  /// toolbar changed underneath it.
  ///
  /// The fix is to stop living inside that capsule. This label pads itself, the
  /// two controls built on it (`ToolbarCaptionButton`, `ToolbarCaptionMenu`) draw
  /// their own glass around it, and `ToolbarCaptionItem` hides the shared
  /// background the toolbar would otherwise clip them with. It is why this is
  /// the one module in the package that imposes glass: the capsule is not
  /// decoration here, it replaces a system one that no longer fits.
  ///
  /// The controls build this for you. It is public so an app with a third kind
  /// of trigger can draw the same label rather than a sixth copy of it.
  public struct ToolbarCaptionLabel: View {
    private let caption: LocalizedStringKey
    private let value: String?
    private let placeholder: LocalizedStringKey
    private let systemImage: String
    private let showsIndicator: Bool

    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.isEnabled) private var isEnabled

    /// - Parameters:
    ///   - caption: what the control sets — "Model", "Tune". A key, resolved in
    ///     the app's catalog.
    ///   - value: what it is set to, drawn verbatim. It is data — a model's name,
    ///     a summary like "c=0.50 nms=0.50" — not a sentence to translate. Nil or
    ///     blank draws `placeholder` instead.
    ///   - placeholder: the second line when there is no value, in the secondary
    ///     style so it reads as an absence rather than as a choice.
    ///   - systemImage: the leading glyph.
    ///   - showsIndicator: a small accent dot on the capsule, for a control whose
    ///     settings differ from their defaults. Silhouette's canvas and tune
    ///     buttons carry one.
    public init(
      _ caption: LocalizedStringKey,
      value: String?,
      placeholder: LocalizedStringKey,
      systemImage: String,
      showsIndicator: Bool = false
    ) {
      self.caption = caption
      self.value = value
      self.placeholder = placeholder
      self.systemImage = systemImage
      self.showsIndicator = showsIndicator
    }

    public var body: some View {
      let displayed = Self.displayedValue(value)
      // System toolbar items dim with their window. A plain button style does
      // not do that for a custom label, so an inactive or disabled control steps
      // its text down a level itself, or it stays bright beside dimmed
      // neighbours.
      let muted = !appearsActive || !isEnabled

      HStack(alignment: .center, spacing: 6) {
        Image(systemName: systemImage)
          .foregroundStyle(muted ? HierarchicalShapeStyle.secondary : .primary)
        VStack(alignment: .leading, spacing: 0) {
          Text(caption)
            .font(.caption2)
            .foregroundStyle(muted ? HierarchicalShapeStyle.tertiary : .secondary)
          Group {
            if let displayed {
              Text(verbatim: displayed)
            } else {
              Text(placeholder)
            }
          }
          .font(.callout)
          .foregroundStyle(
            displayed == nil || muted ? HierarchicalShapeStyle.secondary : .primary
          )
          .lineLimit(1)
        }
        // Offered one line's height, the stack truncates to "Model…". Asking for
        // its ideal height is what keeps both lines.
        .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 4)
      .overlay(alignment: .topTrailing) {
        if showsIndicator {
          Circle()
            .fill(Color.accentColor)
            .frame(width: 7, height: 7)
            .padding(.top, 4)
            .padding(.trailing, 8)
            .accessibilityHidden(true)
        }
      }
      .contentShape(.capsule)
      .accessibilityElement(children: .combine)
    }

    /// The value to draw, or nil when the placeholder should take the line.
    ///
    /// Blank counts as absent: a second line with nothing on it reads as a
    /// control that failed to load rather than one that is unset. A real value
    /// is returned untouched — trimming it would rewrite data.
    nonisolated static func displayedValue(_ value: String?) -> String? {
      guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return nil
      }
      return value
    }
  }

  extension View {
    /// The capsule both caption controls draw in place of the toolbar's.
    /// Interactive, so hover and press still answer the pointer the way the
    /// bordered style they replace did.
    func toolbarCaptionCapsule() -> some View {
      glassEffect(.regular.interactive(), in: .capsule)
    }
  }
#endif
