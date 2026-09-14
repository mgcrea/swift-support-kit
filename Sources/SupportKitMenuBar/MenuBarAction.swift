#if os(macOS)
  import SwiftUI

  /// One thing the footer can do.
  ///
  /// The type exists for one reason above the others: **`title` is not
  /// optional.** Three apps in the fleet shipped icon-only footer buttons
  /// carrying `.help()` and no `.accessibilityLabel`, so VoiceOver announced
  /// them as "gearshape" and "list.bullet.rectangle". Bastion's comment even
  /// asserted that "the tooltips and the shortcuts carry the names" — a tooltip
  /// is not an accessibility label, and the same bug was written three times
  /// because each app spelled the button out by hand. A button built from this
  /// cannot be unlabelled.
  ///
  /// The second reason is `helpText`. Every app hard-coded the shortcut into its
  /// tooltip as literal text — `"Settings (⌘,)"` — so the tooltip and the
  /// `keyboardShortcut` were two independent statements of one fact, free to
  /// drift the first time either moved. Here the tooltip is composed from the
  /// shortcut that is actually applied.
  public struct MenuBarAction: Identifiable {
    /// Three things at once, as `SettingsPane`'s raw value is: the `ForEach`
    /// identity, the tail of the accessibility identifier, and the name a test
    /// asserts on. A `UUID` would supply the first and neither of the others,
    /// and would change on every rebuild.
    public let id: String

    /// The button's name — its accessibility label, and the base of its tooltip.
    ///
    /// `LocalizedStringKey` rather than `String`, for the reason documented on
    /// `SettingsPane.title`: a `String` hands SwiftUI a finished sentence rather
    /// than a catalog key, which is English, in French, with nothing failing to
    /// say so.
    public let title: LocalizedStringKey

    /// The glyph, or nil for a button that spells its name.
    ///
    /// This is what separates the two kinds of footer entry. A **route** carries
    /// a glyph and sits in the action row; a **verb** spells itself and stacks
    /// above it. See `MenuBarFooter`.
    public let systemImage: String?

    public let shortcut: KeyEquivalent?
    public let modifiers: EventModifiers
    public let isDisabled: Bool
    public let run: () -> Void

    public init(
      id: String,
      title: LocalizedStringKey,
      systemImage: String? = nil,
      shortcut: KeyEquivalent? = nil,
      modifiers: EventModifiers = .command,
      isDisabled: Bool = false,
      run: @escaping () -> Void
    ) {
      self.id = id
      self.title = title
      self.systemImage = systemImage
      self.shortcut = shortcut
      self.modifiers = modifiers
      self.isDisabled = isDisabled
      self.run = run
    }

    // MARK: - The routes the fleet already shares
    //
    // These two titles are this package's own words, so they are translated
    // here from its catalog and handed over as a key that already is the
    // translation. `title` stays a `LocalizedStringKey` for the app's own verbs,
    // which resolve in the app's catalog; a key that catalog does not hold draws
    // itself. A literal here would be looked up in the app's catalog and stay
    // English wherever the app does not happen to carry "Settings".

    /// ⌘, — the gear. Every panel has one.
    public static func settings(_ run: @escaping () -> Void) -> Self {
      Self(
        id: "settings",
        title: LocalizedStringKey(localized("Settings")),
        systemImage: "gearshape",
        shortcut: ",",
        run: run
      )
    }

    /// ⌘L — the call log. Bastion and cupertino both argued their way to this
    /// one independently: every line in those panels is a count of calls, and
    /// "what were those calls" is the only question a summary raises and cannot
    /// answer.
    public static func logs(_ run: @escaping () -> Void) -> Self {
      Self(
        id: "logs",
        title: LocalizedStringKey(localized("Logs")),
        systemImage: "list.bullet.rectangle",
        shortcut: "l",
        run: run
      )
    }

    /// A verb: something this panel *does*, which stacks above the action row
    /// because it needs its name. "Collect now", "Refresh Now".
    public static func verb(
      id: String,
      title: LocalizedStringKey,
      systemImage: String,
      isDisabled: Bool = false,
      run: @escaping () -> Void
    ) -> Self {
      Self(id: id, title: title, systemImage: systemImage, isDisabled: isDisabled, run: run)
    }

    // MARK: - Rendering

    /// The tooltip: the name, then the shortcut that is actually bound.
    ///
    /// `Text` concatenation rather than string interpolation, because the name
    /// has to stay a catalog key while the shortcut glyphs must not be
    /// translated. `LocalizedStringKey` cannot interpolate another
    /// `LocalizedStringKey`, so this is also the only spelling that works.
    public var helpText: Text {
      guard let shortcut else { return Text(title) }
      return Text(title)
        + Text(verbatim: " (\(Self.glyphs(for: modifiers))\(Self.name(of: shortcut)))")
    }

    /// Standard glyph order, as the menu bar draws it: ⌃⌥⇧⌘.
    static func glyphs(for modifiers: EventModifiers) -> String {
      var out = ""
      if modifiers.contains(.control) { out += "⌃" }
      if modifiers.contains(.option) { out += "⌥" }
      if modifiers.contains(.shift) { out += "⇧" }
      if modifiers.contains(.command) { out += "⌘" }
      return out
    }

    /// Uppercased, as a menu item shows it — and harmless for the punctuation
    /// keys, where uppercasing is the identity.
    static func name(of shortcut: KeyEquivalent) -> String {
      String(shortcut.character).uppercased()
    }
  }
#endif
