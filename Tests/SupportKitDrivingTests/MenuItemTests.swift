#if os(macOS)
  import AppKit
  import Testing

  @testable import SupportKitDriving

  /// A shortcut is matched against the main menu without trusting the menu's
  /// own enabled state. An app that is not active has no key window, so
  /// automatic validation finds no target and disables Select All, Copy and
  /// the rest, which is how Cmd-A selected nothing through the channel
  /// (Cupertino's `make channel-check`, 2026-11-11). The item is found here;
  /// whether its action applies is asked of the explicit target.
  @Suite @MainActor struct MenuItemTests {
    func menu(_ item: NSMenuItem) -> NSMenu {
      let edit = NSMenu(title: "Edit")
      edit.autoenablesItems = false
      edit.addItem(item)
      let holder = NSMenuItem()
      holder.submenu = edit
      let main = NSMenu()
      main.addItem(holder)
      return main
    }

    @Test func findsAnItemValidationWouldHaveDisabled() {
      let selectAll = NSMenuItem(
        title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
      selectAll.isEnabled = false
      #expect(
        EventSynthesis.menuItem(in: menu(selectAll), key: "a", flags: [.command]) === selectAll)
    }

    /// A menu that does not enable its items automatically, as a SwiftUI
    /// command menu does not, means what its `isEnabled` says: a shortcut the
    /// app greyed out on purpose is not fired.
    @Test func anItemTheAppDisabledIsNotUsable() {
      let delete = NSMenuItem(
        title: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "d")
      // Held: an item's `menu` is weak, and a dropped menu would send the item
      // to the text view's own validation instead.
      let holder = menu(delete)
      withExtendedLifetime(holder) {
        delete.isEnabled = false
        #expect(!EventSynthesis.isUsable(delete, target: NSTextView()))
        delete.isEnabled = true
        #expect(EventSynthesis.isUsable(delete, target: NSTextView()))
      }
    }

    /// In a menu that enables automatically, the target decides, as AppKit's
    /// own validation would from the key window.
    @Test func anAutoEnabledItemAsksTheTarget() {
      let selectAll = NSMenuItem(
        title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
      let edit = NSMenu(title: "Edit")
      edit.addItem(selectAll)
      selectAll.isEnabled = false
      #expect(EventSynthesis.isUsable(selectAll, target: NSTextView()))
    }

    @Test func theModifiersMustMatch() {
      let item = NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
      #expect(EventSynthesis.menuItem(in: menu(item), key: "v", flags: [.command, .shift]) == nil)
    }

    @Test func anUppercaseEquivalentCarriesShift() {
      let item = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
      #expect(
        EventSynthesis.menuItem(in: menu(item), key: "z", flags: [.command, .shift]) === item)
    }
  }
#endif
