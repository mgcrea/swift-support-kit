import SwiftUI

#if os(iOS)
  import UIKit
#elseif os(macOS)
  import AppKit
#endif

/// The colours a group can take, by the token a group model stores and syncs. Cadence's,
/// Valise's and Carbone's groups share the set, so the apps colour alike.
public enum GroupPalette {
  /// Every token, in the order a picker shows them. A model stores these words, so they stay
  /// English whatever the app's language.
  public static let tokens = [
    "gray", "blue", "indigo", "purple", "pink", "red", "orange", "yellow", "green", "teal",
  ]

  /// A token as a colour. A token this build does not know, from a group a newer app wrote,
  /// is gray.
  public static func color(_ token: String) -> Color {
    switch token {
    case "blue": .blue
    case "indigo": .indigo
    case "purple": .purple
    case "pink": .pink
    case "red": .red
    case "orange": .orange
    case "yellow": .yellow
    case "green": .green
    case "teal": .teal
    default: .gray
    }
  }

  /// What VoiceOver calls a token, in the app's language.
  public static func name(_ token: String) -> String {
    switch token {
    case "blue": localized("Blue")
    case "indigo": localized("Indigo")
    case "purple": localized("Purple")
    case "pink": localized("Pink")
    case "red": localized("Red")
    case "orange": localized("Orange")
    case "yellow": localized("Yellow")
    case "green": localized("Green")
    case "teal": localized("Teal")
    default: localized("Gray")
    }
  }

  /// A swatch for a palette-style `Picker`, drawn in its token's colour.
  ///
  /// Both platforms draw a palette picker's images as templates, which drops their
  /// `foregroundStyle`: in a Form every swatch came out black on iOS (Valise's screenshots,
  /// 2026-10-13) and light gray on the Mac (2026-11-24). An image already drawn in its colour
  /// keeps it. `GroupColorGrid` draws its swatches by hand and needs none of this.
  public static func swatch(_ token: String) -> Image {
    #if os(iOS)
      if let image = UIImage(systemName: "circle.fill")?
        .withTintColor(UIColor(color(token)), renderingMode: .alwaysOriginal)
      {
        return Image(uiImage: image)
      }
    #elseif os(macOS)
      let config = NSImage.SymbolConfiguration(textStyle: .body)
        .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(color(token))]))
      if let symbol = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config)
      {
        // A drawing-handler image is not a template, so the picker leaves its colour alone.
        let image = NSImage(size: symbol.size, flipped: false) { rect in
          symbol.draw(in: rect)
          return true
        }
        image.accessibilityDescription = name(token)
        return Image(nsImage: image)
      }
    #endif
    return Image(systemName: "circle.fill")
  }
}
