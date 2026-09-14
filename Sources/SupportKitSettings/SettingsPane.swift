import SwiftUI

/// One page of an app's settings window.
///
/// An app declares an enum, gives each case a title and a glyph, and gets the
/// sidebar, the persisted selection, the accessibility identifiers and the
/// deep-linking for free:
///
/// ```swift
/// enum SettingsPane: String, SupportKitSettings.SettingsPane {
///     case general, models, about, licence
///
///     var title: LocalizedStringKey {
///         switch self {
///         case .general: "General"
///         case .models: "Models"
///         case .about: "About"
///         case .licence: "Licence"
///         }
///     }
///     var systemImage: String {
///         switch self {
///         case .general: "gearshape"
///         case .models: "shippingbox"
///         case .about: "info.circle"
///         case .licence: "key"
///         }
///     }
///     var group: SettingsPaneGroup { self == .licence ? .entitlement : .configuration }
///     static var defaultPane: Self { .general }
/// }
/// ```
///
/// `RawValue == String` because the raw value is three things at once: what is
/// written to `UserDefaults`, what a screenshot stage names, and the tail of the
/// accessibility identifier. An `Int` raw value would make all three change
/// meaning when a case is inserted.
public protocol SettingsPane: RawRepresentable, Identifiable, Hashable, CaseIterable, Sendable
where RawValue == String, AllCases: RandomAccessCollection {
  /// The sidebar row and the detail heading both draw this.
  ///
  /// `LocalizedStringKey`, **not** `String`. Handing SwiftUI a `String` hands
  /// it a finished sentence rather than a catalog key — which is English, in
  /// French, with nothing failing to say so. The key resolves in the **app's**
  /// catalog, which is right: the app names its panes. The strings this package
  /// names itself are the opposite case and live in the package's own catalog —
  /// see `localized(_:)`. This requirement is the one reason the protocol cannot
  /// live in `SupportKit` beside the rest of the Foundation-only code.
  var title: LocalizedStringKey { get }

  /// The SF Symbol for the sidebar row.
  var systemImage: String { get }

  /// Which sidebar section this pane sits in. Defaults to `.configuration`.
  var group: SettingsPaneGroup { get }

  /// A count drawn on the sidebar row, or zero for none.
  ///
  /// Zero rather than an optional because `.badge(0)` draws nothing, so an
  /// unread count needs no branch at the call site and a row can never end up
  /// carrying an empty pill. Defaults to zero, so eleven of the twelve apps
  /// never mention it.
  var badge: Int { get }

  /// The pane shown when nothing is stored.
  ///
  /// A protocol requirement rather than `allCases.first`, because which pane
  /// settings opens on must be a stated fact. Two apps in the fleet already
  /// hold this as a named constant precisely so a staged screenshot cannot
  /// land somewhere the OS happened to restore.
  static var defaultPane: Self { get }
}

extension SettingsPane {
  public var id: String { rawValue }
  public var group: SettingsPaneGroup { .configuration }
  public var badge: Int { 0 }

  /// The stored string resolved to a case, falling back to `defaultPane`.
  ///
  /// Note what this does not do: it does not write the fallback back. A raw
  /// value that matches nothing is almost always a case that was renamed or a
  /// build that was rolled back, and rewriting it destroys the only record of
  /// where the user actually was. Falling back is free; forgetting is not.
  static func resolving(_ rawValue: String) -> Self {
    Self(rawValue: rawValue) ?? .defaultPane
  }

  /// The groups that actually hold a pane, in `order`.
  static var occupiedGroups: [SettingsPaneGroup] {
    var seen: [SettingsPaneGroup] = []
    for pane in allCases where !seen.contains(pane.group) {
      seen.append(pane.group)
    }
    return seen.sorted()
  }

  /// The panes in one group, in declaration order.
  static func panes(in group: SettingsPaneGroup) -> [Self] {
    allCases.filter { $0.group == group }
  }
}

/// A sidebar section.
///
/// Two statics rather than an enum with two cases, so an app can slot a group
/// between them without waiting for a package release — `.entitlement` sits at
/// `1_000` for exactly that reason.
///
/// **There is deliberately no header.** Every app in the fleet draws its
/// settings sidebar sections unlabelled, so the field would be dead weight; and
/// the obvious way to add one later is worse than it looks. A `String` header
/// would have to reach `Text` through `LocalizedStringKey(runtimeString)`, which
/// resolves at runtime but is invisible to Xcode's string extractor — so it
/// would never be written into the catalog, and the two bilingual apps would
/// ship an English header past a `check-strings` gate that had nothing to check.
/// A `LocalizedStringKey` field would be right, and cannot be stored here while
/// SwiftUI leaves that type neither `Hashable` nor `Sendable`.
public struct SettingsPaneGroup: Hashable, Comparable, Sendable {
  /// Sections are drawn in ascending `order`. It is also the group's identity.
  public let order: Int

  public init(order: Int) {
    self.order = order
  }

  /// How the app behaves. Everything, unless it is a receipt.
  public static let configuration = SettingsPaneGroup(order: 0)

  /// What was bought — licence, Pro, restore — which is a different question.
  ///
  /// Four apps in the fleet arrived at exactly this split independently and
  /// wrote the same paragraph about it: somebody opens Licence because of a
  /// refusal or a receipt, never because they are tuning something. A third
  /// group is deliberately absent, because no app has yet made a third
  /// distinction.
  public static let entitlement = SettingsPaneGroup(order: 1_000)

  public static func < (lhs: SettingsPaneGroup, rhs: SettingsPaneGroup) -> Bool {
    lhs.order < rhs.order
  }
}
