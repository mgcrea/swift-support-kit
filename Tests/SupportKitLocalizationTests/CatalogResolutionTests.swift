import Foundation
import Testing

/// Compiles each catalog and reads the result — see `CompiledCatalog` for why the
/// lookup does not go through `Bundle.module`.
@Suite("String catalogs compile and resolve", .enabled(if: CompiledCatalog.isAvailable))
struct CatalogResolutionTests {
  /// A malformed catalog, or a French value whose format specifiers disagree with
  /// its key's, fails here rather than in the next app build that links it.
  @Test("Catalogs compile", arguments: CatalogScanner.Module.all)
  func catalogCompiles(module: CatalogScanner.Module) throws {
    try CompiledCatalog.compile(module)
  }

  /// Spot-checks in the language that is *not* the source. If the catalog were
  /// wired wrongly these would be absent from the compiled table, and a French
  /// app would fall back to the English key.
  @Test(
    "French resolves",
    arguments: [
      (CatalogScanner.Module.ui, "Send Feedback…", "Envoyer un commentaire…"),
      (CatalogScanner.Module.settings, "Version", "Version"),
      (CatalogScanner.Module.settings, "System", "Système"),
      (CatalogScanner.Module.menuBar, "Quit", "Quitter"),
    ])
  func frenchResolves(module: CatalogScanner.Module, key: String, expected: String) throws {
    let french = try CompiledCatalog.table(for: module, language: "fr")
    #expect(french[key] == expected)
  }

  /// The app's name is interpolated into these, and French puts it somewhere
  /// else in the sentence. The specifier has to survive compilation for that to
  /// work at all.
  @Test("Interpolated keys keep their specifier")
  func interpolationSurvivesCompilation() throws {
    let ui = try CompiledCatalog.table(for: .ui, language: "fr")
    #expect(ui["%@ Help"] == "Aide de %@")
    #expect(ui["%@ Support"] == "Assistance %@")

    let menuBar = try CompiledCatalog.table(for: .menuBar, language: "fr")
    #expect(menuBar["About %@"] == "À propos de %@")
  }

  /// English is the source language, so it needs no authored entries — but the
  /// compiled `en` table still has to exist, because it is what an app in neither
  /// language falls back to.
  @Test("Both languages compile", arguments: CatalogScanner.Module.all)
  func bothLanguagesCompile(module: CatalogScanner.Module) throws {
    let languages = try CompiledCatalog.compiledLanguages(for: module)
    #expect(languages.contains("en"), "\(module.name) compiled no English table")
    #expect(languages.contains("fr"), "\(module.name) compiled no French table")
  }
}
