import Foundation

/// Compiles a module's `.xcstrings` the way Xcode does, and hands back the tables.
///
/// This indirection exists because the two build systems this package is built by
/// disagree. **Xcode** runs `xcstringstool` over each catalog and lands
/// `en.lproj/Localizable.strings` and `fr.lproj/Localizable.strings` inside the
/// package's resource bundle, which is what a shipped app carries. **SwiftPM** does
/// not: `swift build` copies the `.xcstrings` into the bundle verbatim, so
/// `Bundle.module` under `swift test` holds a file `NSLocalizedString` cannot read
/// and every lookup falls back to its key.
///
/// A resolution test written against `Bundle.module` would therefore fail under
/// `swift test` while the app it guards is fine — a test that cries wolf, gets
/// deleted, and leaves nothing checking the translations. So the catalog is
/// compiled here with the tool Xcode uses, and read out of the result. balise
/// found this first, in `BaliseLocalizationTests`.
enum CompiledCatalog {
  /// `xcstringstool` ships inside Xcode rather than the Swift toolchain, so it is
  /// located through `xcrun` and its absence skips the suite rather than crashing.
  static var isAvailable: Bool { toolURL != nil }

  private static var toolURL: URL? {
    let xcrun = Process()
    xcrun.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    xcrun.arguments = ["--find", "xcstringstool"]
    let output = Pipe()
    xcrun.standardOutput = output
    xcrun.standardError = FileHandle.nullDevice
    do {
      try xcrun.run()
    } catch {
      return nil
    }
    xcrun.waitUntilExit()
    guard xcrun.terminationStatus == 0 else { return nil }
    let path = String(
      decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    return path.isEmpty ? nil : URL(fileURLWithPath: path)
  }

  /// The compiled key → value table for one language.
  ///
  /// Reads the `.strings` file rather than asking a `Bundle`, because
  /// `Bundle.localizedString(forKey:value:table:)` resolves against the process's
  /// preferred languages: on an English machine it returns English whichever
  /// language the test meant to check, and passes while proving nothing.
  static func table(
    for module: CatalogScanner.Module, language: String
  ) throws -> [String: String] {
    let output = try compile(module)
    let strings = output.appending(path: "\(language).lproj/Localizable.strings")
    guard FileManager.default.fileExists(atPath: strings.path) else { return [:] }
    return NSDictionary(contentsOf: strings) as? [String: String] ?? [:]
  }

  /// The languages the catalog actually compiled to.
  static func compiledLanguages(for module: CatalogScanner.Module) throws -> Set<String> {
    let output = try compile(module)
    let entries = try FileManager.default.contentsOfDirectory(
      at: output, includingPropertiesForKeys: nil)
    return Set(
      entries
        .filter { $0.pathExtension == "lproj" }
        .map { $0.deletingPathExtension().lastPathComponent }
    )
  }

  /// Compiled fresh into a directory unique to each call. The suite runs its tests
  /// in parallel, so a directory keyed by module alone would have two tests
  /// compiling into it at once.
  @discardableResult
  static func compile(_ module: CatalogScanner.Module) throws -> URL {
    guard let toolURL else {
      throw CatalogError.toolUnavailable
    }
    let output = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "supportkit-catalog-\(module.name)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

    let compile = Process()
    compile.executableURL = toolURL
    compile.arguments = [
      "compile", CatalogScanner.catalogURL(for: module).path, "-o", output.path,
    ]
    let errors = Pipe()
    compile.standardError = errors
    compile.standardOutput = FileHandle.nullDevice
    try compile.run()
    compile.waitUntilExit()

    let diagnostics = String(
      decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    guard compile.terminationStatus == 0 else {
      throw CatalogError.compilationFailed(module: module.name, diagnostics: diagnostics)
    }
    return output
  }

  enum CatalogError: Error, CustomStringConvertible {
    case toolUnavailable
    case compilationFailed(module: String, diagnostics: String)

    var description: String {
      switch self {
      case .toolUnavailable:
        "xcstringstool was not found; Xcode is required to compile a String Catalog."
      case .compilationFailed(let module, let diagnostics):
        "\(module)'s Localizable.xcstrings does not compile:\n\(diagnostics)"
      }
    }
  }
}
