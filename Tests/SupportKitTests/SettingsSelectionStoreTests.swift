import Foundation
import Testing

@testable import SupportKit

/// A private `UserDefaults` per test, so these never touch the real domain and
/// never depend on each other's leftovers.
private func scratchDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
  let defaults = UserDefaults(suiteName: name)!
  defaults.removePersistentDomain(forName: name)
  return defaults
}

private func store(
  _ defaults: UserDefaults,
  key: String = "app.settingsPane",
  legacy: [String] = []
) -> SettingsSelectionStore {
  SettingsSelectionStore(
    key: key, defaultRawValue: "general", legacyKeys: legacy, defaults: defaults)
}

@Suite("Settings selection")
struct SettingsSelectionStoreTests {
  @Test("falls back to the default when nothing is stored")
  func defaultsWhenEmpty() {
    #expect(store(scratchDefaults()).rawValue == "general")
  }

  @Test("round-trips a selection")
  func roundTrip() {
    let subject = store(scratchDefaults())
    subject.select("licence")
    #expect(subject.rawValue == "licence")
  }

  @Test("reset forgets the stored pane")
  func resetForgets() {
    let subject = store(scratchDefaults())
    subject.select("licence")
    subject.reset()
    #expect(subject.rawValue == "general")
  }

  // MARK: - Migration
  //
  // Three apps shipped a bare `settingsPane` before this existed. Getting the
  // move wrong is the quietest failure in the whole rollout: the pane resets,
  // which looks like nothing at all until it is the app whose first-run licence
  // prompt deep-links through this key.

  @Test("moves a legacy value under the canonical key and removes the old one")
  func migratesLegacyValue() {
    let defaults = scratchDefaults()
    defaults.set("licence", forKey: "settingsPane")

    let subject = store(defaults, legacy: ["settingsPane"])

    #expect(subject.rawValue == "licence")
    #expect(defaults.string(forKey: "settingsPane") == nil)
  }

  /// The property that makes migration safe to run on every launch. Copying
  /// unconditionally would let the legacy value keep winning, quietly undoing
  /// the user's pane change on the launch after they made it — a symptom that
  /// reads as a SwiftUI bug rather than a migration one.
  @Test("does not re-migrate over a newer choice")
  func migrationIsIdempotent() {
    let defaults = scratchDefaults()
    defaults.set("licence", forKey: "settingsPane")

    let first = store(defaults, legacy: ["settingsPane"])
    first.select("updates")

    let second = store(defaults, legacy: ["settingsPane"])
    #expect(second.rawValue == "updates")
  }

  @Test("leaves the canonical value alone when both keys are present")
  func canonicalWins() {
    let defaults = scratchDefaults()
    defaults.set("updates", forKey: "app.settingsPane")
    defaults.set("licence", forKey: "settingsPane")

    let subject = store(defaults, legacy: ["settingsPane"])

    #expect(subject.rawValue == "updates")
    #expect(defaults.string(forKey: "settingsPane") == nil)
  }

  @Test("takes the first legacy key that holds a value")
  func firstLegacyKeyWins() {
    let defaults = scratchDefaults()
    defaults.set("audit", forKey: "oldest")
    defaults.set("licence", forKey: "older")

    let subject = store(defaults, legacy: ["older", "oldest"])

    #expect(subject.rawValue == "licence")
    #expect(defaults.string(forKey: "older") == nil)
    #expect(defaults.string(forKey: "oldest") == nil)
  }

  @Test("does nothing when there is nothing to migrate")
  func nothingToMigrate() {
    let defaults = scratchDefaults()
    let subject = store(defaults, legacy: ["settingsPane"])
    #expect(subject.migrateIfNeeded() == nil)
    #expect(subject.rawValue == "general")
  }

  /// An unrecognised value is a renamed case or a rolled-back build. Falling
  /// back is free; rewriting the stored value destroys the only record of where
  /// the user actually was, and a rollback would then land on the default.
  @Test("keeps an unrecognised value stored rather than rewriting it")
  func doesNotRewriteUnknownValues() {
    let defaults = scratchDefaults()
    let subject = store(defaults)
    subject.select("a-pane-that-was-renamed")

    #expect(subject.rawValue == "a-pane-that-was-renamed")
    #expect(defaults.string(forKey: "app.settingsPane") == "a-pane-that-was-renamed")
  }

  @Test("two apps sharing a defaults domain do not collide")
  func namespacedKeysDoNotCollide() {
    let defaults = scratchDefaults()
    let one = store(defaults, key: "bastion.settingsPane")
    let two = store(defaults, key: "cupertino.settingsPane")

    one.select("licence")
    two.select("permissions")

    #expect(one.rawValue == "licence")
    #expect(two.rawValue == "permissions")
  }
}
