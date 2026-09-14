import Foundation
import Testing

/// Source ↔ catalog agreement, for every UI module. No module is imported here:
/// this is a file-on-disk comparison, so it cannot be fooled by a lookup that
/// happens to resolve at runtime because the host bundle carried the same key.
@Suite("String catalogs match their call sites")
struct CatalogDriftTests {
  @Test("Every localized call site has a catalog entry", arguments: CatalogScanner.Module.all)
  func everyCallSiteIsInTheCatalog(module: CatalogScanner.Module) throws {
    let catalog = Set(
      try CatalogScanner.catalogKeys(for: module).keys.map(CatalogScanner.normalized))
    let missing = try CatalogScanner.sourceKeys(for: module)
      .filter { !catalog.contains(CatalogScanner.normalized($0)) }
      .sorted()

    #expect(
      missing.isEmpty,
      """
      \(module.name) looks up \(missing.count) string(s) that its catalog does not declare. \
      Each one silently draws English in a French app. Add them to \
      Sources/\(module.name)/Resources/Localizable.xcstrings:
      \(missing.map { "  • \($0)" }.joined(separator: "\n"))
      """
    )
  }

  @Test("Every catalog entry is still used", arguments: CatalogScanner.Module.all)
  func everyCatalogEntryHasACallSite(module: CatalogScanner.Module) throws {
    let sources = Set(try CatalogScanner.sourceKeys(for: module).map(CatalogScanner.normalized))
    let orphaned = try CatalogScanner.catalogKeys(for: module).keys
      .filter { !sources.contains(CatalogScanner.normalized($0)) }
      .sorted()

    #expect(
      orphaned.isEmpty,
      """
      \(module.name)'s catalog declares \(orphaned.count) string(s) no longer looked up \
      anywhere. Delete them, or check whether a call site was reworded without the catalog \
      following:
      \(orphaned.map { "  • \($0)" }.joined(separator: "\n"))
      """
    )
  }

  /// Xcode 26 generates a Swift symbol for every manual entry, and two keys that
  /// differ only in punctuation — "Send Feedback" and "Send Feedback…" — map to
  /// the same symbol. That is a hard build error in every app that links the
  /// module, and nothing here would see it: `swift build` never generates symbols,
  /// so CI and this suite stay green while the apps break. The package looks every
  /// string up through `localized(_:)` and uses no symbol, so every entry opts out.
  @Test("Symbol generation is off for every entry", arguments: CatalogScanner.Module.all)
  func symbolGenerationIsOff(module: CatalogScanner.Module) throws {
    let generating = try CatalogScanner.keysGeneratingSymbols(for: module)

    #expect(
      generating.isEmpty,
      """
      \(module.name) has \(generating.count) entr(y/ies) without "generatesSymbol": false. \
      Xcode builds a Swift symbol for each, and a collision breaks every app that links it:
      \(generating.map { "  • \($0)" }.joined(separator: "\n"))
      """
    )
  }

  @Test("Catalogs are authored in English", arguments: CatalogScanner.Module.all)
  func sourceLanguageIsEnglish(module: CatalogScanner.Module) throws {
    #expect(try CatalogScanner.sourceLanguage(for: module) == "en")
  }

  /// A half-translated catalog is worse than an untranslated one: the host app
  /// then mixes the two languages in the same window, and the package is the
  /// part it cannot fix.
  @Test("French is complete", arguments: CatalogScanner.Module.all)
  func frenchIsComplete(module: CatalogScanner.Module) throws {
    let untranslated = try CatalogScanner.catalogKeys(for: module)
      .filter { !$0.value.contains("fr") }
      .keys.sorted()

    #expect(
      untranslated.isEmpty,
      """
      \(module.name) has \(untranslated.count) string(s) with no translated French value:
      \(untranslated.map { "  • \($0)" }.joined(separator: "\n"))
      """
    )
  }

  @Test("No string literal reaches SwiftUI unlocalized", arguments: CatalogScanner.Module.all)
  func noBareLiterals(module: CatalogScanner.Module) throws {
    let offenders = try CatalogScanner.bareLiterals(in: module)

    #expect(
      offenders.isEmpty,
      """
      \(module.name) hands \(offenders.count) literal(s) straight to SwiftUI. A literal \
      there is looked up in the host app's catalog, not this package's, and draws English \
      in a French app. Wrap each in localized(…) and add it to the catalog, or use \
      Text(verbatim:) for text that must not be translated:
      \(offenders.map { "  • \($0)" }.joined(separator: "\n"))
      """
    )
  }
}

extension CatalogScanner.Module: CustomTestStringConvertible {
  var testDescription: String { name }
}
