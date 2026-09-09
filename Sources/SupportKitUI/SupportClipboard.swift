#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

/// Putting text on the pasteboard, under one name.
///
/// This existed three times already — verbatim, in balise, dev-pulse and
/// r2-explorer — because SwiftUI has no pasteboard API of its own. `.copyable`
/// needs a focused view and a `Transferable`, which is a different shape from
/// "copy this string when the button is pressed", so the bridge is unavoidable
/// rather than merely convenient. The About pane's copy button needs it, and a
/// fourth copy was the alternative.
@MainActor
public enum SupportClipboard {
  /// Replaces the pasteboard contents with `text`.
  ///
  /// `clearContents()` first on macOS is not optional and has no UIKit
  /// counterpart: an `NSPasteboard` accumulates representations, and writing
  /// without clearing leaves the previous item's other types in place for a
  /// paste target to prefer. The symptom is a paste that yields something the
  /// user copied two actions ago, which reads as the button not having worked.
  /// `UIPasteboard.string` replaces the item outright.
  public static func copy(_ text: String) {
    #if os(macOS)
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.setString(text, forType: .string)
    #else
      UIPasteboard.general.string = text
    #endif
  }
}
