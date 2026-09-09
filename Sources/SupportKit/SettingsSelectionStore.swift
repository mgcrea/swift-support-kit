import Foundation

/// Which settings pane is showing, and how a deep link aims at one.
///
/// Foundation rather than SwiftUI, and that is the whole reason this type exists
/// separately from `SettingsSelection`. Two of the consuming apps are
/// `LSUIElement` and build their settings window by hand: they write the pane
/// from an `NSWindowController` before any view has been created, so a
/// SwiftUI-only API could not serve the call site that needs it most.
///
/// ## The mechanism
///
/// The write moves the sidebar; opening the window is a separate act. Every
/// deep link in the fleet is therefore two lines, in this order:
///
/// ```swift
/// Support.settings.select(.licence)
/// openSettings()                      // or the app's own window controller
/// ```
///
/// Writing *before* opening is not a style preference. The settings view binds
/// through `@AppStorage`, which observes the defaults domain, so the write lands
/// whether the window is being built for the first time or has been sitting
/// behind Xcode for an hour. Reversing the two, or mirroring the value into
/// `@State`, is exactly how a deep link into an already-open window stops
/// working — and it fails only for the already-open case, which is the one
/// nobody tests.
/// `@unchecked` because `UserDefaults` carries no `Sendable` conformance while
/// being documented as thread-safe. Every stored property here is either a `let`
/// of a value type or that one reference, so the unchecked part is precisely the
/// gap between Foundation's annotation and its documentation — not a claim about
/// this type's own contents. It has to be `Sendable` at all because apps hold it
/// as a `static let` beside their `SupportApp`.
public struct SettingsSelectionStore: @unchecked Sendable {
  /// The canonical key. Namespace it with the app's slug.
  public let key: String

  /// What a missing — or unrecognised — value falls back to.
  private let defaultRawValue: String

  /// Keys this app shipped under before `key`.
  private let legacyKeys: [String]

  private let defaults: UserDefaults

  /// - Parameters:
  ///   - key: the canonical key. Use `"<slug>.settingsPane"`.
  ///   - defaultRawValue: the pane shown when nothing is stored.
  ///   - legacyKeys: keys this app shipped under before. Read once, moved,
  ///     removed. An app that has always used `key` passes none.
  ///   - defaults: injectable so a test never writes into the developer's own
  ///     domain, the same way `ReviewPrompt` takes it.
  public init(
    key: String,
    defaultRawValue: String,
    legacyKeys: [String] = [],
    defaults: UserDefaults = .standard
  ) {
    self.key = key
    self.defaultRawValue = defaultRawValue
    self.legacyKeys = legacyKeys
    self.defaults = defaults
    migrateIfNeeded()
  }

  /// The stored raw value, or `defaultRawValue` when nothing is stored.
  ///
  /// Note what this does **not** do: it does not validate the string against
  /// the app's pane cases, and it does not write anything back. Both are
  /// deliberate — see `SettingsSelection.pane`.
  public var rawValue: String {
    defaults.string(forKey: key) ?? defaultRawValue
  }

  /// Aim settings at a pane. Call this **before** opening the window.
  public func select(_ rawValue: String) {
    defaults.set(rawValue, forKey: key)
  }

  /// Move a legacy key's value under `key`, then remove the legacy key.
  ///
  /// Called from `init`, and exposed only so a test can drive it directly.
  ///
  /// Migration happens **only when the canonical key holds nothing**, which is
  /// what makes it idempotent. Copying on every launch instead would quietly
  /// undo the user's pane change on the next one — the legacy value would keep
  /// winning, and the symptom ("settings keeps going back to General") reads
  /// like a SwiftUI bug rather than a migration one.
  ///
  /// The legacy key is then removed. A build rolled back past this change
  /// therefore starts on its default pane once; that is the whole cost, and it
  /// buys a defaults domain where the dead key cannot be read by mistake.
  ///
  /// - Returns: the value that was moved, or nil when there was nothing to do.
  @discardableResult
  public func migrateIfNeeded() -> String? {
    let alreadyMigrated = defaults.string(forKey: key) != nil
    var moved: String?
    for legacy in legacyKeys {
      guard let value = defaults.string(forKey: legacy) else { continue }
      if !alreadyMigrated, moved == nil {
        defaults.set(value, forKey: key)
        moved = value
      }
      defaults.removeObject(forKey: legacy)
    }
    return moved
  }

  /// Forget the stored pane. The next read returns `defaultRawValue`.
  public func reset() {
    defaults.removeObject(forKey: key)
  }
}
