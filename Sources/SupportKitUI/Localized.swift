import Foundation

/// Looks a string up in **this module's** catalog.
///
/// `String(localized:)` defaults to `Bundle.main`, which inside a package is the
/// host app's bundle: the lookup finds no entry, falls back to the key, and draws
/// English to a French user with no build error and no crash. Naming `.module` is
/// the whole reason this function exists. Each UI module keeps its own copy,
/// because `Bundle.module` resolves to the module the code is compiled into.
///
/// It returns `String` rather than `LocalizedStringResource` so that one spelling
/// serves every call site: `Text`, `Label`, `Link`, `Button`, `LabeledContent`,
/// `.help` and `.accessibilityLabel` all take a `StringProtocol` and draw it
/// verbatim. The key is the English text, so the source still reads as what an
/// English user sees.
///
/// The cost is that Xcode's extractor now sees this function's parameter rather
/// than the call site's literal, so nothing fills the catalog on build. Entries
/// are written by hand and marked `manual`, and `SupportKitLocalizationTests` does
/// the extractor's job instead: it fails on a call site with no entry, an entry
/// with no call site, a key with no French, and a literal handed straight to
/// SwiftUI. It is the arrangement balise's BaliseKit already ships.
func localized(_ key: String.LocalizationValue) -> String {
  String(localized: key, bundle: .module)
}
