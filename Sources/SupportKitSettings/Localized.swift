import Foundation

/// Looks a string up in **this module's** catalog. See `SupportKitUI`'s
/// `Localized.swift` for why every UI module carries its own copy.
///
/// `@usableFromInline` because `SettingsScaffold`'s `rootTitle` defaults to this
/// module's "Settings", and a public default argument may only reach symbols the
/// caller's module can see. The body is still compiled here, so `.module` is still
/// this package's bundle.
@usableFromInline
func localized(_ key: String.LocalizationValue) -> String {
  String(localized: key, bundle: .module)
}
