import Foundation
import SwiftUI
import Testing
import UniformTypeIdentifiers

@testable import SupportKitSidebar

@Suite("Group palette")
struct GroupPaletteTests {
  /// Group models store and sync these words; renaming one recolours every group that had it.
  @Test func theTokensAreTheOnesGroupsStore() {
    #expect(
      GroupPalette.tokens == [
        "gray", "blue", "indigo", "purple", "pink", "red", "orange", "yellow", "green", "teal",
      ])
  }

  @Test func everyTokenButGrayHasAColourOfItsOwn() {
    let drawn = GroupPalette.tokens.map(GroupPalette.color)
    #expect(Set(drawn.map(\.description)).count == GroupPalette.tokens.count)
    #expect(GroupPalette.color("gray") == .gray)
  }

  /// A token from a newer app draws gray rather than failing.
  @Test func anUnknownTokenIsGray() {
    #expect(GroupPalette.color("chartreuse") == .gray)
    #expect(GroupPalette.name("chartreuse") == GroupPalette.name("gray"))
  }

  @Test func everyTokenHasAName() {
    let names = GroupPalette.tokens.map(GroupPalette.name)
    #expect(Set(names).count == GroupPalette.tokens.count)
    #expect(GroupPalette.name("teal") == "Teal")
  }
}

@Suite("Section outline")
struct SectionOutlineTests {
  @Test func aCollapsedHeaderClosesTheOutlineOnItsOwn() {
    #expect(SectionOutline.header(isCollapsed: true) == [.top, .bottom])
  }

  @Test func onlyTheLastRowClosesTheBottom() {
    #expect(SectionOutline.row(isFirst: false, isLast: true).contains(.bottom))
    #expect(!SectionOutline.row(isFirst: false, isLast: false).contains(.bottom))
  }

  #if os(macOS)
    /// On the Mac the header is the outline's top, so no row draws one.
    @Test func theMacHeaderIsTheTop() {
      #expect(SectionOutline.header(isCollapsed: false) == .top)
      #expect(SectionOutline.row(isFirst: true, isLast: false) == .sides)
    }
  #endif
}

@Suite("Internal drag reference")
struct InternalDragReferenceTests {
  struct Reference: InternalDragReference {
    static var contentType: UTType {
      UTType(exportedAs: "io.mgcrea.tests.reference", conformingTo: .data)
    }
    let id: UUID
  }

  @Test func aReferenceRoundTrips() throws {
    let reference = Reference(id: UUID())
    let data = try JSONEncoder().encode(reference)
    #expect(try JSONDecoder().decode(Reference.self, from: data).id == reference.id)
  }

  @Test func itIsExportedAsTheAppsOwnType() async throws {
    let reference = Reference(id: UUID())
    let data = try await reference.exported(as: Reference.contentType)
    #expect(try JSONDecoder().decode(Reference.self, from: data).id == reference.id)
  }
}
