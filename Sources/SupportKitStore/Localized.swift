import Foundation

/// Looks a string up in **this module's** catalog. See `SupportKitUI`'s
/// `Localized.swift` for why every module that shows text carries its own copy.
func localized(_ key: String.LocalizationValue) -> String {
  String(localized: key, bundle: .module)
}
