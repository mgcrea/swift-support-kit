import Foundation
import SupportKit

/// The typed face of `SettingsSelectionStore`.
///
/// An app declares one beside its `SupportApp` and hands it to the scaffold:
///
/// ```swift
/// enum Support {
///     static let app = SupportApp(slug: "cupertino", displayName: "Cupertino", …)
///     static let settings = SettingsSelection<SettingsPane>(
///         app: app,
///         legacyKeys: ["settingsPane"]
///     )
/// }
/// ```
///
/// A value the app holds rather than statics on the protocol, for the reason
/// `ReviewPrompt` takes a `defaults:` — a test must not write into the
/// developer's own domain, and an implicit key cannot be pointed somewhere else
/// when an app already has a second selection-shaped store of its own.
public struct SettingsSelection<Pane: SettingsPane>: Sendable {
  private let store: SettingsSelectionStore

  /// - Parameters:
  ///   - key: the canonical defaults key.
  ///   - legacyKeys: keys this app shipped under before. See the hazard note
  ///     on `init(app:legacyKeys:defaults:)`.
  public init(key: String, legacyKeys: [String] = [], defaults: UserDefaults = .standard) {
    store = SettingsSelectionStore(
      key: key,
      defaultRawValue: Pane.defaultPane.rawValue,
      legacyKeys: legacyKeys,
      defaults: defaults
    )
  }

  /// The key becomes `"<app.slug>.settingsPane"`.
  ///
  /// Namespaced, because three apps in the fleet shipped a bare
  /// `"settingsPane"` — a key plausible enough that any app might have taken
  /// it, and two of those three run on the same Mac. Those three must pass
  /// `legacyKeys: ["settingsPane"]`; an app already namespaced passes none.
  /// Forget it and the pane silently resets, which is harmless in most apps
  /// and is not in the one whose first-run licence prompt deep-links through
  /// this key.
  public init(app: SupportApp, legacyKeys: [String] = [], defaults: UserDefaults = .standard) {
    self.init(key: "\(app.slug).settingsPane", legacyKeys: legacyKeys, defaults: defaults)
  }

  /// The stored pane, or `Pane.defaultPane`.
  public var pane: Pane { Pane.resolving(store.rawValue) }

  /// Aim settings at a pane. Call this **before** opening the window.
  public func select(_ pane: Pane) { store.select(pane.rawValue) }

  /// The defaults key, for the scaffold's `@AppStorage`.
  public var storageKey: String { store.key }

  /// Forget the stored pane.
  public func reset() { store.reset() }
}
