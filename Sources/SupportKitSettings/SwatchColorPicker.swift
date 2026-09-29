import SwiftUI

#if canImport(AppKit)
  import AppKit
#endif

/// A colour row for Settings: the label, a chip that opens a few swatches chosen for what is
/// being coloured, a hex field for anything else, and the system panel past that. The default is
/// the first swatch, and a colour moved off it can be put back from the row.
///
/// `set(nil)` means "the default": the caller removes its key rather than storing the default's
/// hex, so a later change to the default reaches everyone who never picked.
public struct SwatchColorPicker: View {
  private let label: Text
  private let value: SwatchColor
  private let fallback: SwatchColor
  private let palette: [SwatchColor]
  private let supportsOpacity: Bool
  private let set: (SwatchColor?) -> Void

  @State private var isPresented = false
  @Environment(\.isEnabled) private var isEnabled

  #if canImport(AppKit)
    @State private var panel = ColourPanelLink()
  #endif

  public init(
    _ titleKey: LocalizedStringKey, value: SwatchColor, default fallback: SwatchColor,
    palette: [SwatchColor], supportsOpacity: Bool = false, set: @escaping (SwatchColor?) -> Void
  ) {
    self.init(
      label: Text(titleKey), value: value, fallback: fallback, palette: palette,
      supportsOpacity: supportsOpacity, set: set)
  }

  public init<Title: StringProtocol>(
    _ title: Title, value: SwatchColor, default fallback: SwatchColor, palette: [SwatchColor],
    supportsOpacity: Bool = false, set: @escaping (SwatchColor?) -> Void
  ) {
    self.init(
      label: Text(title), value: value, fallback: fallback, palette: palette,
      supportsOpacity: supportsOpacity, set: set)
  }

  private init(
    label: Text, value: SwatchColor, fallback: SwatchColor, palette: [SwatchColor],
    supportsOpacity: Bool, set: @escaping (SwatchColor?) -> Void
  ) {
    self.label = label
    self.value = value
    self.fallback = fallback
    self.palette = palette
    self.supportsOpacity = supportsOpacity
    self.set = set
  }

  /// Compared as stored, so a colour that went through the picker and back to the default's
  /// bytes counts as the default.
  private var isDefault: Bool { value.hex == fallback.hex }

  public var body: some View {
    HStack {
      label
      Spacer()
      // Kept in the layout while hidden, so the chips of a column stay lined up.
      Button {
        choose(nil)
      } label: {
        Image(systemName: "arrow.uturn.backward")
      }
      .buttonStyle(.borderless)
      .help(localized("Restore the default colour"))
      .accessibilityLabel(localized("Restore the default colour"))
      .opacity(isDefault ? 0 : 1)
      .disabled(isDefault)

      Button {
        isPresented = true
      } label: {
        ColourChip(colour: value)
          .frame(width: 38, height: 20)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(label)
      .accessibilityValue(value.typed(withAlpha: supportsOpacity))
      .popover(isPresented: $isPresented, arrowEdge: .bottom) {
        SwatchPopover(
          value: value, swatches: SwatchColorPicker.swatches(fallback, palette),
          fallback: fallback, supportsOpacity: supportsOpacity, choose: choose,
          more: more)
      }
    }
    .opacity(isEnabled ? 1 : 0.5)
  }

  private func choose(_ colour: SwatchColor?) {
    guard let colour, colour.hex != fallback.hex else { return set(nil) }
    set(supportsOpacity ? colour : colour.withAlpha(1))
  }

  /// The system's own picker, for the eyedropper and the wheel. On the Mac the panel outlives
  /// the popover it was opened from, so the link to it belongs to the row.
  private func more() {
    #if canImport(AppKit)
      isPresented = false
      panel.open(value, showsAlpha: supportsOpacity) { choose($0) }
    #endif
  }

  /// The default first, then the palette without it.
  public nonisolated static func swatches(_ fallback: SwatchColor, _ palette: [SwatchColor])
    -> [SwatchColor]
  {
    [fallback] + palette.filter { $0.hex != fallback.hex }
  }
}

private struct SwatchPopover: View {
  let value: SwatchColor
  let swatches: [SwatchColor]
  let fallback: SwatchColor
  let supportsOpacity: Bool
  let choose: (SwatchColor?) -> Void
  let more: () -> Void

  @State private var typed = ""
  @FocusState private var isTyping: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 6), count: 6), spacing: 6) {
        ForEach(Array(swatches.enumerated()), id: \.offset) { index, swatch in
          swatchButton(swatch, isDefault: index == 0)
        }
      }

      Divider()

      HStack(spacing: 8) {
        TextField(
          localized("Hex"), text: $typed,
          prompt: Text(verbatim: supportsOpacity ? "#RRGGBBAA" : "#RRGGBB")
        )
        .labelsHidden()
        .monospaced()
        .autocorrectionDisabled()
        .focused($isTyping)
        .frame(width: supportsOpacity ? 110 : 90)
        .onSubmit(commit)
        .onChange(of: isTyping) { _, typing in if !typing { commit() } }
        Spacer()
        #if canImport(AppKit)
          Button(localized("More…"), action: more)
        #else
          ColorPicker(
            localized("More…"),
            selection: Binding(get: { value.color }, set: { choose(SwatchColor($0)) }),
            supportsOpacity: supportsOpacity)
        #endif
      }
    }
    .padding(12)
    .frame(width: 6 * 26 + 5 * 6 + 24)
    .onAppear { typed = value.typed(withAlpha: supportsOpacity) }
    .onChange(of: value) { _, new in
      if !isTyping { typed = new.typed(withAlpha: supportsOpacity) }
    }
  }

  private func swatchButton(_ swatch: SwatchColor, isDefault: Bool) -> some View {
    let shown = colour(for: swatch)
    let isCurrent = shown.hex == value.hex
    return Button {
      choose(shown)
    } label: {
      ColourChip(colour: shown)
        .frame(width: 26, height: 26)
        .overlay {
          RoundedRectangle(cornerRadius: 6)
            .inset(by: -3)
            .strokeBorder(Color.accentColor, lineWidth: 2)
            .opacity(isCurrent ? 1 : 0)
        }
        .overlay(alignment: .bottomTrailing) {
          if isDefault {
            Circle()
              .fill(Color.primary)
              .overlay(Circle().strokeBorder(Color(white: 1), lineWidth: 1))
              .frame(width: 8, height: 8)
              .offset(x: 2, y: 2)
          }
        }
    }
    .buttonStyle(.plain)
    .help(
      isDefault
        ? Text(localized("Default colour"))
        : Text(verbatim: shown.typed(withAlpha: supportsOpacity))
    )
    .accessibilityLabel(
      isDefault
        ? Text(localized("Default colour"))
        : Text(verbatim: shown.typed(withAlpha: supportsOpacity)))
  }

  /// A swatch picked for something see-through keeps how see-through it is, unless it was
  /// fully clear: a clear tint made brick would still show nothing.
  private func colour(for swatch: SwatchColor) -> SwatchColor {
    guard supportsOpacity, value.alpha > 0, swatch.hex != fallback.hex else { return swatch }
    return swatch.withAlpha(value.alpha)
  }

  private func commit() {
    guard let parsed = SwatchColor(typed: typed) else {
      typed = value.typed(withAlpha: supportsOpacity)
      return
    }
    // Six digits typed for a see-through colour keep its opacity, as a swatch does.
    let digits = typed.trimmingCharacters(in: .whitespaces).drop { $0 == "#" }.count
    let colour =
      supportsOpacity && digits != 8 && value.alpha > 0 ? parsed.withAlpha(value.alpha) : parsed
    choose(colour)
    typed = colour.typed(withAlpha: supportsOpacity)
  }
}

/// A colour as a rounded tile, over a checkerboard where it lets the background through.
private struct ColourChip: View {
  let colour: SwatchColor

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 5)
    ZStack {
      if colour.alpha < 1 {
        Canvas { context, size in
          let side = 5.0
          for row in 0..<Int((size.height / side).rounded(.up)) {
            for column in 0..<Int((size.width / side).rounded(.up))
            where (row + column).isMultiple(of: 2) {
              context.fill(
                Path(
                  CGRect(x: Double(column) * side, y: Double(row) * side, width: side, height: side)
                ),
                with: .color(.gray.opacity(0.35)))
            }
          }
        }
        .background(Color(white: 1))
      }
      colour.color
    }
    .clipShape(shape)
    .overlay(shape.strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
  }
}

#if canImport(AppKit)
  /// The shared colour panel, pointed at the row that last opened it. The panel keeps no strong
  /// hold on its target, so the link lets go of it when the row goes.
  @MainActor
  final class ColourPanelLink: NSObject {
    /// Which link the panel reports to, since the panel only sets its target.
    private static var owner: ObjectIdentifier?

    private var changed: ((SwatchColor) -> Void)?

    func open(_ colour: SwatchColor, showsAlpha: Bool, changed: @escaping (SwatchColor) -> Void) {
      let panel = NSColorPanel.shared
      // Pointed away first, so setting its colour does not echo back as a pick.
      panel.setTarget(nil)
      panel.showsAlpha = showsAlpha
      panel.color = NSColor(
        srgbRed: colour.red, green: colour.green, blue: colour.blue, alpha: colour.alpha)
      self.changed = changed
      panel.setTarget(self)
      Self.owner = ObjectIdentifier(self)
      panel.setAction(#selector(colourChanged(_:)))
      panel.orderFront(nil)
    }

    @objc private func colourChanged(_ sender: NSColorPanel) {
      guard let colour = sender.color.usingColorSpace(.sRGB) else { return }
      changed?(
        SwatchColor(
          colour.redComponent, colour.greenComponent, colour.blueComponent,
          colour.alphaComponent))
    }

    deinit {
      MainActor.assumeIsolated {
        guard Self.owner == ObjectIdentifier(self) else { return }
        NSColorPanel.shared.setTarget(nil)
        Self.owner = nil
      }
    }
  }
#endif
