import SwiftUI
import Testing

@testable import SupportKitSettings

/// A pane set shaped like the fleet's: several configuration panes and one
/// entitlement pane, declared out of group order on purpose.
private enum Pane: String, SettingsPane {
  case general, about, licence, activity

  var title: LocalizedStringKey {
    switch self {
    case .general: "General"
    case .about: "About"
    case .licence: "Licence"
    case .activity: "Activity"
    }
  }

  var systemImage: String {
    switch self {
    case .general: "gearshape"
    case .about: "info.circle"
    case .licence: "key"
    case .activity: "list.bullet.rectangle"
    }
  }

  var group: SettingsPaneGroup {
    self == .licence ? .entitlement : .configuration
  }

  static var defaultPane: Pane { .general }
}

/// An app with one group — bloat-buster's shape.
private enum SmallPane: String, SettingsPane {
  case exclusions, about

  var title: LocalizedStringKey { self == .exclusions ? "Exclusions" : "About" }
  var systemImage: String { self == .exclusions ? "nosign" : "info.circle" }
  static var defaultPane: SmallPane { .exclusions }
}

@Suite("Settings pane")
struct SettingsPaneTests {
  @Test("resolves a stored raw value")
  func resolves() {
    #expect(Pane.resolving("licence") == .licence)
  }

  @Test("falls back to the declared default, not the first case")
  func fallsBackToDefault() {
    #expect(Pane.resolving("a-renamed-case") == .general)
  }

  @Test("orders groups by order, not by declaration")
  func groupOrder() {
    #expect(Pane.occupiedGroups == [.configuration, .entitlement])
  }

  /// The rule the scaffold keys on: one occupied group draws no `Section`, so
  /// an app with a single group never gets a divider through the middle of it.
  @Test("reports a single occupied group for a single-group app")
  func singleGroup() {
    #expect(SmallPane.occupiedGroups == [.configuration])
  }

  @Test("keeps declaration order inside a group")
  func declarationOrderWithinGroup() {
    #expect(Pane.panes(in: .configuration) == [.general, .about, .activity])
    #expect(Pane.panes(in: .entitlement) == [.licence])
  }

  @Test("defaults every pane to the configuration group")
  func defaultGroup() {
    #expect(SmallPane.about.group == .configuration)
  }

  @Test("defaults every pane to no badge")
  func defaultBadge() {
    #expect(Pane.allCases.allSatisfy { $0.badge == 0 })
  }

  /// A group is its order. An app that labels the same group at one call site
  /// and not at another must not end up with two sections claiming `order: 0`.
  @Test("identifies a group by its order")
  func groupIdentity() {
    #expect(SettingsPaneGroup(order: 0) == .configuration)
    #expect(SettingsPaneGroup(order: 0) < .entitlement)
  }

  /// The raw value is the defaults value, the screenshot stage name and the
  /// tail of the accessibility identifier at once.
  @Test("uses the raw value as the identity")
  func idIsRawValue() {
    #expect(Pane.licence.id == "licence")
  }
}
