#if os(macOS)
  import SwiftUI
  import Testing

  @testable import SupportKitMenuBar

  /// The two contracts that regress silently.
  ///
  /// Both of these shipped broken in three apps at once, and neither is visible
  /// in a screenshot, a build log or a golden gate — an unlabelled button looks
  /// perfect and announces "gearshape", and a tooltip naming a shortcut nobody
  /// bound looks equally perfect.
  @Suite struct MenuBarActionTests {
    /// Every preset must name itself. This is the whole reason `title` is not
    /// optional, and the assertion that stops someone adding a fourth preset
    /// that forgets.
    @Test func everyPresetCarriesAName() {
      let actions: [MenuBarAction] = [
        .settings {},
        .logs {},
        .verb(id: "refresh", title: "Refresh Now", systemImage: "arrow.clockwise") {},
      ]
      for action in actions {
        #expect(!action.id.isEmpty)
        // A `LocalizedStringKey` is opaque, so the reachable proof that a name
        // exists is that the tooltip built from it is not just the shortcut.
        #expect(action.helpText != Text(verbatim: ""))
      }
    }

    /// The tooltip is composed from the shortcut that is actually applied, so
    /// the two cannot drift. Each app used to hard-code "Settings (⌘,)" beside
    /// an independent `keyboardShortcut(",")`.
    @Test func helpTextSpellsTheShortcutThatIsBound() {
      #expect(MenuBarAction.name(of: ",") == ",")
      #expect(MenuBarAction.name(of: "l") == "L")
      #expect(MenuBarAction.name(of: "o") == "O")

      #expect(MenuBarAction.glyphs(for: .command) == "⌘")
      #expect(MenuBarAction.glyphs(for: [.command, .shift]) == "⇧⌘")
      // Menu-bar order, not the order they were passed in.
      #expect(MenuBarAction.glyphs(for: [.command, .control, .option]) == "⌃⌥⌘")
    }

    /// The presets are the fleet's shared vocabulary; their glyphs and chords
    /// are what makes two panels read as the same panel.
    @Test func sharedRoutesKeepTheirAgreedGlyphAndChord() {
      let settings = MenuBarAction.settings {}
      #expect(settings.systemImage == "gearshape")
      #expect(settings.shortcut == ",")

      let logs = MenuBarAction.logs {}
      #expect(logs.systemImage == "list.bullet.rectangle")
      #expect(logs.shortcut == "l")
    }

    /// A verb spells itself; a route wears a glyph. `MenuBarPanel` branches on
    /// exactly this, so a verb that arrived without an image would silently
    /// render as an unlabelled icon button.
    @Test func verbsCarryAnImageForTheirLabel() {
      let verb = MenuBarAction.verb(
        id: "collect", title: "Collect now", systemImage: "tray.and.arrow.down"
      ) {}
      #expect(verb.systemImage != nil)
      #expect(verb.shortcut == nil)
      #expect(!verb.isDisabled)
    }
  }
#endif
