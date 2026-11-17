#if os(macOS)
  import AppKit
  import Foundation
  import SupportKitTestHost
  import Testing

  @testable import SupportKitDriving

  /// A driven copy keeps the person's saved windows apart; a person's copy is left as it was.
  @Suite("Driven launch") @MainActor
  struct DrivenLaunchTests {

    @Test func readsTheArgumentsTheChannelReads() {
      for value in ["YES", "yes", "true", "1"] {
        #expect(DrivenLaunch.isRequested(["App", "-DrivingChannel", value]), "\(value)")
      }
      for value in ["NO", "no", "false", "0", "maybe"] {
        #expect(!DrivenLaunch.isRequested(["App", "-DrivingChannel", value]), "\(value)")
      }
      #expect(!DrivenLaunch.isRequested(["App", "-DrivingChannel"]))
      #expect(!DrivenLaunch.isRequested(["App", "-DrivingChannelX", "YES"]))
      #expect(!DrivenLaunch.isRequested(["App"]))
    }

    /// The test runner asked for no channel.
    @Test func thisLaunchIsNotDriven() {
      #expect(!DrivenLaunch.isRequestedAtLaunch)
    }

    /// Driven, `ApplePersistenceIgnoreState` is registered, and nothing is written to the
    /// preferences the person's copy shares; not driven, nothing is registered at all.
    @Test func aDrivenLaunchRestoresNothing() throws {
      let driven = "driving-\(UUID())"
      let plain = "driving-\(UUID())"
      defer {
        UserDefaults.standard.removePersistentDomain(forName: driven)
        UserDefaults.standard.removePersistentDomain(forName: plain)
      }
      let defaults = try #require(RegisteringDefaults(suiteName: driven))
      DrivenLaunch.prepare(arguments: ["App", "-DrivingChannel", "YES"], defaults: defaults)
      #expect(defaults.registered[DrivenLaunch.ignoresSavedStateKey] as? Bool == true)
      #expect(defaults.registered.count == 1)
      #expect(
        defaults.persistentDomain(forName: driven)?[DrivenLaunch.ignoresSavedStateKey] == nil)

      let fresh = try #require(RegisteringDefaults(suiteName: plain))
      DrivenLaunch.prepare(arguments: ["App"], defaults: fresh)
      #expect(fresh.registered.isEmpty)
    }

    /// A person's window stays restorable; a driven copy's is kept from saving.
    @Test func onlyADrivenCopysWindowsStopSaving() {
      let window = HostedWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 100))
      defer { window.close() }
      window.isRestorable = true
      DrivenLaunch.keepFromSaving([window])
      #expect(window.isRestorable)
      DrivenLaunch.keepFromSaving([window], requested: true)
      #expect(!window.isRestorable)
    }
  }

  /// Records what is registered, which `UserDefaults` does not let a test read back apart from
  /// the other domains.
  private final class RegisteringDefaults: UserDefaults, @unchecked Sendable {
    var registered: [String: Any] = [:]

    override func register(defaults registrationDictionary: [String: Any]) {
      registered.merge(registrationDictionary) { _, new in new }
      super.register(defaults: registrationDictionary)
    }
  }
#endif
