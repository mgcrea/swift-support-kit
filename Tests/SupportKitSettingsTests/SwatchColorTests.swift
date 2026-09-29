import SwiftUI
import Testing

@testable import SupportKitSettings

/// The colour a settings row stores and shows, what a person types into it, and the swatches it
/// offers.
@Suite("Swatch colour")
struct SwatchColorTests {

  @Test func writesAndReadsItsStoredHex() {
    let colour = SwatchColor.hex(0x1F2A44)
    #expect(colour.hex == "1F2A44FF")
    #expect(SwatchColor(hex: colour.hex) == colour)
    #expect(SwatchColor(hex: "1F2A44")?.hex == "1F2A44FF")
    #expect(SwatchColor.hex(0x112233, alpha: 0.6).hex == "11223399")
  }

  @Test(arguments: ["", "12345", "GGHHII", "#1F2A44", "1F2A44F"])
  func refusesAStoredHexItDidNotWrite(_ text: String) {
    #expect(SwatchColor(hex: text) == nil)
  }

  @Test func readsSixDigitsWithOrWithoutTheHash() {
    #expect(SwatchColor(typed: "#112233")?.hex == "112233FF")
    #expect(SwatchColor(typed: "112233")?.hex == "112233FF")
    #expect(SwatchColor(typed: "  #aabbcc ")?.hex == "AABBCCFF")
  }

  @Test func readsTheCSSShorthand() {
    #expect(SwatchColor(typed: "#abc")?.hex == "AABBCCFF")
  }

  @Test func readsTheOpacityLast() {
    #expect(SwatchColor(typed: "#C0504D99")?.hex == "C0504D99")
  }

  @Test(arguments: ["", "#", "#12", "#12345", "#1234567", "#GGHHII", "red", "##112233"])
  func refusesAnythingElseTyped(_ text: String) {
    #expect(SwatchColor(typed: text) == nil)
  }

  @Test func showsOpacityOnlyWhereItIsAskedForAndNotFull() {
    #expect(SwatchColor.hex(0x112233).typed(withAlpha: false) == "#112233")
    #expect(SwatchColor.hex(0x112233).typed(withAlpha: true) == "#112233")
    #expect(SwatchColor.hex(0x112233, alpha: 0.6).typed(withAlpha: true) == "#11223399")
    #expect(SwatchColor.hex(0x112233, alpha: 0.6).typed(withAlpha: false) == "#112233")
  }

  @Test func putsTheDefaultFirstAndOnlyOnce() {
    let fallback = SwatchColor.hex(0xF7F5ED)
    let palette = [SwatchColor.hex(0xFFFFFF), .hex(0xF7F5ED), .hex(0xEDEAE3)]
    let swatches = SwatchColorPicker.swatches(fallback, palette)
    #expect(swatches.first == fallback)
    #expect(swatches.filter { $0.hex == fallback.hex }.count == 1)
    #expect(swatches.count == 3)
  }

  /// A colour picked in the system panel comes back through `Color`, so it must survive the
  /// trip to within what the stored hex can tell apart.
  @Test func survivesATripThroughColor() {
    let colour = SwatchColor.hex(0x4A3B2A)
    #expect(SwatchColor(colour.color).hex == colour.hex)
  }
}
