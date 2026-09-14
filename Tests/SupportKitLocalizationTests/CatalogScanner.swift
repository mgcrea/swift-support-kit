import Foundation

/// Reads a module's sources and its String Catalog off disk and compares the two.
///
/// This exists because `localized("…")` hides the literal from Xcode's extractor:
/// the extractor sees the wrapper's parameter, not the call site's text, so nothing
/// fills these catalogs on build. The entries are written by hand, and a
/// hand-written catalog fails silently — a key with no entry falls back to the
/// key, which is English, which looks fine to whoever wrote it and wrong to every
/// French user.
///
/// So the check the extractor would have given for free is done here, in both
/// directions, plus one it would not: a literal handed straight to SwiftUI, which
/// resolves in the host app's bundle and never reaches this package's catalog at
/// all. Ported from balise's `BaliseLocalizationTests`, which found every trap
/// documented below first.
enum CatalogScanner {
  /// A UI target, laid out as `Sources/<name>/Resources/Localizable.xcstrings`.
  struct Module {
    var name: String

    static let ui = Module(name: "SupportKitUI")
    static let settings = Module(name: "SupportKitSettings")
    static let menuBar = Module(name: "SupportKitMenuBar")

    static let all: [Module] = [.ui, .settings, .menuBar]
  }

  /// `.../Tests/SupportKitLocalizationTests/CatalogScanner.swift` → `.../Sources`.
  private static var sourcesRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: "Sources")
  }

  // MARK: - Catalog

  static func catalogURL(for module: Module) -> URL {
    sourcesRoot
      .appending(path: module.name)
      .appending(path: "Resources/Localizable.xcstrings")
  }

  /// The keys declared in a module's catalog, and the languages each one is
  /// translated into.
  static func catalogKeys(for module: Module) throws -> [String: Set<String>] {
    let data = try Data(contentsOf: catalogURL(for: module))
    let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    let strings = root["strings"] as? [String: Any] ?? [:]

    return strings.reduce(into: [:]) { result, entry in
      let localizations = (entry.value as? [String: Any])?["localizations"] as? [String: Any]
      let translated = (localizations ?? [:]).compactMap { language, value -> String? in
        isTranslated(value) ? language : nil
      }
      result[entry.key] = Set(translated)
    }
  }

  /// Whether one language's entry is fully translated.
  ///
  /// Two shapes, because a pluralized string carries no `stringUnit` of its own:
  /// it carries `variations.plural`, one unit per category, and all of them have
  /// to be translated. Reading only `stringUnit` reports every plural as
  /// untranslated — balise's first version of this did exactly that.
  private static func isTranslated(_ value: Any) -> Bool {
    guard let entry = value as? [String: Any] else { return false }

    if let unit = entry["stringUnit"] as? [String: Any] {
      return unit["state"] as? String == "translated"
    }
    if let plural = (entry["variations"] as? [String: Any])?["plural"] as? [String: Any] {
      return !plural.isEmpty && plural.values.allSatisfy(isTranslated)
    }
    return false
  }

  /// Entries that would have Xcode generate a Swift symbol: any without an
  /// explicit `"generatesSymbol": false`. See `CatalogDriftTests` for why none may.
  static func keysGeneratingSymbols(for module: Module) throws -> [String] {
    let data = try Data(contentsOf: catalogURL(for: module))
    let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    let strings = root["strings"] as? [String: [String: Any]] ?? [:]
    return strings.filter { $0.value["generatesSymbol"] as? Bool != false }.keys.sorted()
  }

  static func sourceLanguage(for module: Module) throws -> String? {
    let data = try Data(contentsOf: catalogURL(for: module))
    let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    return root?["sourceLanguage"] as? String
  }

  // MARK: - Sources

  /// Every key passed to `localized(…)`, as the string Swift will build at runtime.
  ///
  /// A regex rather than a parse of the syntax tree, which sets a real limit: the
  /// literal has to begin at the call, so a key assembled from a variable is
  /// invisible here. That is a constraint on how lookups may be written, not an
  /// approximation — a key the guard cannot see is reported by both directions of
  /// the comparison rather than passed.
  static func sourceKeys(for module: Module) throws -> Set<String> {
    // Both shapes of literal: a one-line `"…"`, and the `"""…"""` block the Help
    // pane's intro is written as. Skipping the block form would leave its entry
    // looking like an orphan.
    let pattern = try NSRegularExpression(
      pattern: #"localized\(\s*(?:"""(.*?)"""|"((?:[^"\\]|\\.)*)")"#,
      options: [.dotMatchesLineSeparators]
    )

    var keys: Set<String> = []
    for file in try swiftFiles(in: module) {
      let source = try code(in: file)
      let range = NSRange(source.startIndex..., in: source)
      for match in pattern.matches(in: source, range: range) {
        if let block = Range(match.range(at: 1), in: source) {
          keys.insert(joinedBlockLiteral(String(source[block])))
        } else if let inline = Range(match.range(at: 2), in: source) {
          keys.insert(String(source[inline]))
        }
      }
    }
    return keys
  }

  /// Every string literal handed to SwiftUI without going through `localized(…)`,
  /// as `File.swift:line  text`.
  ///
  /// This is the regression the rest of the suite cannot see. A literal passed to
  /// `Text`, `Label` or `.help` is a `LocalizedStringKey`, looked up in the HOST
  /// app's bundle: it compiles, it never crashes, it is not a `localized` call so
  /// the drift checks never meet it — and it draws English in a French app. The
  /// patterns are the initializers and modifiers this package actually uses, a
  /// `title:` argument, and a `LocalizedStringKey` declared from a literal.
  /// `Text(verbatim:)` does not match, which is the spelling for text that must
  /// not be translated.
  static func bareLiterals(in module: Module) throws -> [String] {
    let patterns = [
      #"\b(Text|Button|Label|Link|LabeledContent|Section|Toggle|Picker|Menu|NavigationLink)\(\s*""#,
      #"\.(help|accessibilityLabel|accessibilityHint|accessibilityValue|navigationTitle)\(\s*""#,
      #"\btitle:\s*""#,
      #"LocalizedStringKey\??\s*(=|\{)\s*""#,
    ]
    let regex = try NSRegularExpression(pattern: patterns.joined(separator: "|"))

    var offenders: [String] = []
    for file in try swiftFiles(in: module) {
      let source = try code(in: file)
      let range = NSRange(source.startIndex..., in: source)
      for match in regex.matches(in: source, range: range) {
        guard let matched = Range(match.range, in: source) else { continue }
        let line = source[..<matched.lowerBound].count(where: { $0 == "\n" }) + 1
        let text = source[matched].replacingOccurrences(of: "\n", with: " ")
        offenders.append("\(file.lastPathComponent):\(line)  \(text)")
      }
    }
    return offenders.sorted()
  }

  private static func swiftFiles(in module: Module) throws -> [URL] {
    let root = sourcesRoot.appending(path: module.name)
    let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
    var result: [URL] = []
    for case let file as URL in files ?? .init() where file.pathExtension == "swift" {
      result.append(file)
    }
    return result
  }

  /// Resolves a `"""…"""` literal to the string Swift would produce at runtime.
  ///
  /// Only the two rules this package's catalogs rely on: the closing delimiter's
  /// indentation is stripped from every line, and a line ending in `\` continues
  /// onto the next without a newline. Anything else would show up as a mismatch
  /// rather than pass silently.
  private static func joinedBlockLiteral(_ raw: String) -> String {
    let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }

    var result = ""
    for line in lines {
      if line.hasSuffix("\\") {
        result += line.dropLast()
      } else {
        result += line + "\n"
      }
    }
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// A file's contents with whole-line comments blanked.
  ///
  /// Needed because this package documents its code heavily, doc comments
  /// included, and a comment showing `Text("…")` as an example would otherwise be
  /// scanned as a real call site. Blanked rather than removed, so the line numbers
  /// `bareLiterals` reports still match the file. Only lines that are entirely a
  /// comment: stripping a trailing `//` would have to know whether the slashes sit
  /// inside a string literal, and this package writes its explanations above the
  /// code rather than beside it.
  private static func code(in file: URL) throws -> String {
    try String(contentsOf: file, encoding: .utf8)
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map { line in
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let isComment =
          trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*")
        return isComment ? "" : String(line)
      }
      .joined(separator: "\n")
  }

  // MARK: - Comparison

  /// Collapses a source key's `\(…)` interpolations and a catalog key's
  /// `%@`-style specifiers to the same placeholder, so the two spellings of one
  /// string compare equal.
  ///
  /// Interpolations are matched non-greedily and do not handle a nested `)` —
  /// `\(Int(x))` would normalize wrongly. Keys here are written without nested
  /// calls, and this comment is the reason why.
  static func normalized(_ key: String) -> String {
    let placeholder = "\u{FFFC}"
    let interpolation = #"\\\([^)]*\)"#
    let specifier = #"%(\d+\$)?[-+ 0#]*[0-9]*(\.[0-9]+)?(hh|h|ll|l|q|z|t|j)?[@dioufFeEgGxXsScp]"#

    var result = key
    for pattern in [interpolation, specifier] {
      result = result.replacingOccurrences(
        of: pattern, with: placeholder, options: .regularExpression)
    }
    return result
  }
}
