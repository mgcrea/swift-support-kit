import SwiftUI

/// A colour for a settings row: sRGB components in 0...1, stored as `RRGGBBAA` hex so a
/// preference survives a round trip through `UserDefaults` unchanged.
public struct SwatchColor: Hashable, Sendable {
  public var red: Double
  public var green: Double
  public var blue: Double
  public var alpha: Double

  public init(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }

  /// `0xF7F5ED`, the way a design brief writes them.
  public static func hex(_ value: UInt32, alpha: Double = 1) -> SwatchColor {
    SwatchColor(
      Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255,
      Double(value & 0xFF) / 255, alpha)
  }

  /// The stored form: six or eight hex digits, no `#`. Anything else is not ours, so it is
  /// refused rather than guessed at, and the caller falls back to its default.
  public init?(hex text: String) {
    guard text.count == 6 || text.count == 8, text.allSatisfy(\.isHexDigit),
      let value = UInt32(text, radix: 16)
    else { return nil }
    let rgba = text.count == 6 ? value << 8 | 0xFF : value
    self.init(
      Double((rgba >> 24) & 0xFF) / 255, Double((rgba >> 16) & 0xFF) / 255,
      Double((rgba >> 8) & 0xFF) / 255, Double(rgba & 0xFF) / 255)
  }

  /// `RRGGBBAA`, upper case: what a settings key stores.
  public var hex: String {
    func byte(_ component: Double) -> String {
      String(format: "%02X", Int((min(max(component, 0), 1) * 255).rounded()))
    }
    return byte(red) + byte(green) + byte(blue) + byte(alpha)
  }

  /// What a person types: `#` optional, and three, six or eight hex digits. Three is CSS
  /// shorthand, so `#abc` is `#AABBCC`; eight carries the opacity last.
  public init?(typed text: String) {
    var digits = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if digits.hasPrefix("#") { digits.removeFirst() }
    guard digits.allSatisfy(\.isHexDigit) else { return nil }
    switch digits.count {
    case 3: digits = digits.map { "\($0)\($0)" }.joined() + "FF"
    case 6: digits += "FF"
    case 8: break
    default: return nil
    }
    self.init(hex: digits.uppercased())
  }

  /// `#RRGGBB`, with the opacity appended when it is asked for and not full.
  public func typed(withAlpha: Bool) -> String {
    let stored = hex
    return "#" + (withAlpha && stored.suffix(2) != "FF" ? stored : String(stored.prefix(6)))
  }

  /// The same colour at `alpha`, whatever it had.
  public func withAlpha(_ alpha: Double) -> SwatchColor {
    SwatchColor(red, green, blue, alpha)
  }

  public var color: Color {
    Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
  }

  /// What the system picker hands back, in sRGB.
  public init(_ color: Color) {
    let resolved = color.resolve(in: EnvironmentValues())
    self.init(
      Double(resolved.red), Double(resolved.green), Double(resolved.blue),
      Double(resolved.opacity))
  }
}
