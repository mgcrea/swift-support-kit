#if os(macOS)
  import Foundation
  import ServiceManagement
  import SupportKit
  import Testing

  @testable import SupportKitSettings

  /// A private `UserDefaults` per test, so these never touch the real domain and
  /// never depend on each other's leftovers.
  private func scratchDefaults() -> UserDefaults {
    let name = UUID().uuidString
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
  }

  private struct Refused: Error {}

  /// Stands in for `SMAppService.mainApp`, which under `swift test` would be the
  /// test runner registering itself in the developer's Login Items.
  private final class FakeService: LoginItemService {
    var status: SMAppService.Status
    var refuses = false
    private(set) var registrations = 0

    init(_ status: SMAppService.Status = .notRegistered) {
      self.status = status
    }

    func register() throws {
      if refuses { throw Refused() }
      registrations += 1
      status = .enabled
    }

    func unregister() throws {
      if refuses { throw Refused() }
      status = .notRegistered
    }
  }

  private let app = SupportApp(
    slug: "armada",
    displayName: "Armada",
    siteURL: URL(string: "https://armada.mgcrea.io")!
  )

  private let installed = URL(fileURLWithPath: "/Applications/Armada.app")

  @MainActor
  private func item(
    _ service: FakeService,
    _ defaults: UserDefaults,
    legacy: [String] = [],
    at bundleURL: URL = installed
  ) -> LoginItem {
    LoginItem(
      app: app, legacyDesiredKeys: legacy, service: service, defaults: defaults,
      bundleURL: bundleURL)
  }

  @MainActor
  @Suite("Login item")
  struct LoginItemTests {
    @Test("namespaces the intent under the app's slug")
    func key() {
      #expect(item(FakeService(), scratchDefaults()).desiredKey == "armada.launchAtLogin")
    }

    @Test("records the intent only when the service accepts it")
    func recordsOnSuccess() {
      let defaults = scratchDefaults()
      let service = FakeService()
      let subject = item(service, defaults)

      subject.set(true)
      #expect(subject.isEnabled)
      #expect(subject.isDesired)
      #expect(defaults.bool(forKey: subject.desiredKey))

      subject.set(false)
      #expect(!subject.isEnabled)
      #expect(!subject.isDesired)
    }

    /// Somebody who unticks the box and is refused still has an item that
    /// launches; the record must not claim otherwise.
    @Test("a refused call keeps the previous intent and reports the error")
    func refusalChangesNothingRecorded() {
      let service = FakeService(.enabled)
      let subject = item(service, scratchDefaults())
      service.refuses = true

      subject.set(false)
      #expect(subject.isEnabled)
      #expect(subject.isDesired)
      #expect(subject.lastError != nil)

      service.refuses = false
      subject.set(false)
      #expect(subject.lastError == nil)
    }

    /// The upgrade path for every app that registered before it recorded
    /// anything. Without it, the first update after adopting this drops the item
    /// and `healIfNeeded` has no intent to act on.
    @Test("adopts an item already enabled when nothing is recorded")
    func adoptsExistingRegistration() {
      #expect(item(FakeService(.enabled), scratchDefaults()).isDesired)
    }

    @Test("never overwrites a recorded intent with the service's answer")
    func recordedIntentWins() {
      let defaults = scratchDefaults()
      defaults.set(false, forKey: "armada.launchAtLogin")
      #expect(!item(FakeService(.enabled), defaults).isDesired)
    }

    @Test("re-registers once after an update dropped the item")
    func heals() {
      let defaults = scratchDefaults()
      defaults.set(true, forKey: "armada.launchAtLogin")
      let service = FakeService(.notFound)

      #expect(item(service, defaults).healIfNeeded())
      #expect(service.registrations == 1)
      #expect(service.status == .enabled)
    }

    @Test("does not heal what the user never asked for")
    func noHealWithoutIntent() {
      let service = FakeService(.notFound)
      #expect(!item(service, scratchDefaults()).healIfNeeded())
      #expect(service.registrations == 0)
    }

    /// `.requiresApproval` is macOS waiting on the user, or the user having said
    /// no in System Settings. Re-registering changes neither.
    @Test("does not fight an item awaiting approval")
    func noHealAwaitingApproval() {
      let defaults = scratchDefaults()
      defaults.set(true, forKey: "armada.launchAtLogin")
      let service = FakeService(.requiresApproval)
      let subject = item(service, defaults)

      #expect(!subject.healIfNeeded())
      #expect(subject.needsApproval)
      #expect(service.registrations == 0)
    }

    @Test("asks for approval only when the user wanted the item")
    func approvalNeedsIntent() {
      #expect(!item(FakeService(.requiresApproval), scratchDefaults()).needsApproval)
    }

    @Test("does not heal from a location a login item cannot be left at")
    func noHealFromBuildDirectory() {
      let defaults = scratchDefaults()
      defaults.set(true, forKey: "armada.launchAtLogin")
      let service = FakeService(.notFound)
      let derived = URL(fileURLWithPath: "/tmp/DerivedData/Build/Products/Debug/Armada.app")

      #expect(!item(service, defaults, at: derived).healIfNeeded())
      #expect(service.registrations == 0)
    }

    @Test("moves a legacy intent once and removes the old key")
    func migratesLegacyKey() {
      let defaults = scratchDefaults()
      defaults.set(true, forKey: "launchAtLoginDesired")

      let subject = item(FakeService(), defaults, legacy: ["launchAtLoginDesired"])
      #expect(subject.isDesired)
      #expect(defaults.object(forKey: "launchAtLoginDesired") == nil)
    }

    @Test("a legacy key never overwrites the canonical one")
    func legacyDoesNotOverwrite() {
      let defaults = scratchDefaults()
      defaults.set(false, forKey: "armada.launchAtLogin")
      defaults.set(true, forKey: "launchAtLoginDesired")

      #expect(!item(FakeService(), defaults, legacy: ["launchAtLoginDesired"]).isDesired)
      #expect(defaults.object(forKey: "launchAtLoginDesired") == nil)
    }

    @Test("a pinned service reports its status and changes nothing")
    func pinned() throws {
      let service = PinnedLoginItemService(status: .enabled)
      try service.unregister()
      #expect(service.status == .enabled)
    }
  }

  @Suite("Login item location")
  struct LoginItemLocationTests {
    private let home = URL(fileURLWithPath: "/Users/someone")

    @Test("accepts both Applications folders")
    func applications() {
      #expect(LoginItemLocation(bundleURL: installed, home: home) == .applications)
      let user = URL(fileURLWithPath: "/Users/someone/Applications/Armada.app")
      #expect(LoginItemLocation(bundleURL: user, home: home) == .applications)
    }

    @Test("recognises a Gatekeeper translocation")
    func translocated() {
      let url = URL(
        fileURLWithPath: "/private/var/folders/xy/T/AppTranslocation/ABCD/d/Armada.app")
      #expect(LoginItemLocation(bundleURL: url, home: home) == .translocated)
      #expect(!LoginItemLocation.translocated.canRegister)
    }

    /// A prefix test that forgot the trailing slash would accept this.
    @Test("does not mistake a sibling folder for Applications")
    func lookalike() {
      let url = URL(fileURLWithPath: "/Applications Old/Armada.app")
      #expect(LoginItemLocation(bundleURL: url, home: home) == .elsewhere)
    }
  }
#endif
