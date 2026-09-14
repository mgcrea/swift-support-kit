#if os(macOS)
  import Foundation
  import Observation
  import ServiceManagement
  import SupportKit

  /// The part of `SMAppService` a login item uses.
  ///
  /// A protocol so the rules in `LoginItem` can be tested at all:
  /// `SMAppService.mainApp` means whichever bundle is running, and under
  /// `swift test` that is the test runner — a test that toggled it would put
  /// Xcode's testing helper in the developer's own Login Items.
  public protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
  }

  extension SMAppService: LoginItemService {}

  /// A login item that reports a fixed status and changes nothing.
  ///
  /// For screenshot captures, which must neither read nor write the developer's
  /// real registration: a golden that photographs whatever the capturing Mac
  /// happens to have registered churns from one machine to the next.
  public struct PinnedLoginItemService: LoginItemService {
    public let status: SMAppService.Status

    public init(status: SMAppService.Status = .enabled) {
      self.status = status
    }

    public func register() {}
    public func unregister() {}
  }

  /// Where the running bundle is, as far as a login item cares.
  ///
  /// `SMAppService.mainApp` registers the bundle **at its current path**. A copy
  /// Gatekeeper translocated disappears with the session, and one in a build
  /// directory disappears with the next clean — either way the registration
  /// outlives the thing it points at, and nothing says so. Only a copy in an
  /// Applications folder is somewhere a login item can reasonably be left.
  ///
  /// Cupertino measured the neighbouring question and it is NOT this one: a
  /// privacy grant follows the code signature and survives a move. A login item
  /// is a path.
  public enum LoginItemLocation: Equatable, Sendable {
    case applications
    case translocated
    case elsewhere

    public init(
      bundleURL: URL,
      home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
      let path = bundleURL.resolvingSymlinksInPath().path
      if path.contains("/AppTranslocation/") {
        self = .translocated
        return
      }
      let roots = ["/Applications", home.appending(path: "Applications").path]
      self = roots.contains { path.hasPrefix($0 + "/") } ? .applications : .elsewhere
    }

    /// Whether registering from here leaves a login item that will still work.
    public var canRegister: Bool { self == .applications }
  }

  /// Launch at login, for an app that registers itself with `SMAppService`.
  ///
  /// Two facts are kept apart here, because they come apart in practice: what
  /// the user **asked for**, recorded under `<slug>.launchAtLogin`, and what the
  /// service **reports**. A registration is a bundle at a path, and it can drop
  /// when the bundle under it is replaced — which for the three Sparkle apps is
  /// every update. With only the service's answer to go on, the checkbox is
  /// simply unticked the next time somebody opens settings, and the app has
  /// stopped starting at login without anyone being told. Cupertino found that
  /// and fixed it alone; armada had the same exposure and no fix, which is why
  /// this lives in the package now.
  ///
  /// Hold one per app, beside its `SupportApp`, and call `healIfNeeded()` once
  /// from `applicationDidFinishLaunching` — the first moment after an update
  /// when both facts are readable.
  @MainActor
  @Observable
  public final class LoginItem {
    /// The defaults key holding the user's intent. `"<slug>.launchAtLogin"`.
    public let desiredKey: String

    /// Where the running copy is. Read once: an app does not move while it runs.
    public let location: LoginItemLocation

    /// What the service reported at the last read. See `refresh()`.
    public private(set) var status: SMAppService.Status

    /// What the user asked for, as last recorded.
    public private(set) var isDesired: Bool

    /// The last registration failure, in the system's own words. Cleared by the
    /// next call that succeeds.
    public private(set) var lastError: String?

    @ObservationIgnored private let service: any LoginItemService
    @ObservationIgnored private let defaults: UserDefaults

    /// - Parameters:
    ///   - app: names the defaults key.
    ///   - legacyDesiredKeys: Bool keys this app recorded the same intent under
    ///     before. Read once, moved when the canonical key is empty, removed.
    ///     Cupertino passes `["launchAtLoginDesired"]`.
    ///   - service: `SMAppService.mainApp`, or a `PinnedLoginItemService` under a
    ///     screenshot capture.
    ///   - defaults: injectable so a test never writes the developer's domain.
    ///   - bundleURL: the running bundle. Injectable for a capture, which runs
    ///     from a build directory and would otherwise photograph the warning.
    public init(
      app: SupportApp,
      legacyDesiredKeys: [String] = [],
      service: any LoginItemService = SMAppService.mainApp,
      defaults: UserDefaults = .standard,
      bundleURL: URL = Bundle.main.bundleURL
    ) {
      self.desiredKey = "\(app.slug).launchAtLogin"
      self.location = LoginItemLocation(bundleURL: bundleURL)
      self.service = service
      self.defaults = defaults
      self.status = service.status
      self.isDesired = false

      Self.migrate(legacyDesiredKeys, to: desiredKey, in: defaults)

      // An app that registered before it recorded anything — armada and bastion
      // until now, cupertino before its heal — has users whose item is on and
      // whose intent is unrecorded. Adopting what the service reports is what
      // lets `healIfNeeded()` protect them from their very next update; waiting
      // for them to touch the checkbox would protect nobody.
      if defaults.object(forKey: desiredKey) == nil, status == .enabled {
        defaults.set(true, forKey: desiredKey)
      }
      self.isDesired = defaults.bool(forKey: desiredKey)
    }

    /// Whether the service says the app will launch at login.
    ///
    /// What the checkbox shows. Deliberately not `isDesired`: a registration
    /// that did not take has to read as unticked rather than be assumed.
    public var isEnabled: Bool { status == .enabled }

    /// The user asked for it and macOS is holding it until they allow it.
    ///
    /// `.requiresApproval` is also what the service reports after somebody turns
    /// the item off in System Settings, so without the intent this could not
    /// tell "waiting on you" from "you said no there" — and would nag both.
    public var needsApproval: Bool { isDesired && status == .requiresApproval }

    /// Register or unregister, and record the intent if the service accepted it.
    ///
    /// A refused call changes nothing recorded: somebody who unticks the box and
    /// gets an error still has an item that launches, and the record should say
    /// so rather than what they hoped.
    public func set(_ enabled: Bool) {
      do {
        if enabled {
          try service.register()
        } else {
          try service.unregister()
        }
        defaults.set(enabled, forKey: desiredKey)
        isDesired = enabled
        lastError = nil
      } catch {
        lastError = error.localizedDescription
      }
      refresh()
    }

    /// Re-read the service. Call when settings appears, and when the app comes
    /// back from System Settings, where the item can be turned off behind it.
    public func refresh() {
      status = service.status
    }

    /// Re-register once when the user asked for launch at login and the service
    /// no longer agrees.
    ///
    /// One attempt, no retry loop: if it fails, the section shows the real
    /// status and the error, and trying quietly forever would only make a broken
    /// registration harder to notice.
    ///
    /// Skipped for `.requiresApproval`, which re-registering cannot change — it
    /// is macOS waiting on the user, or the user having said no in System
    /// Settings. Skipped from a location a login item cannot be left at, since
    /// registering there is the problem `LoginItemLocation` exists to avoid.
    ///
    /// - Returns: whether a registration was attempted.
    @discardableResult
    public func healIfNeeded() -> Bool {
      refresh()
      guard isDesired, status != .enabled, status != .requiresApproval, location.canRegister
      else { return false }
      set(true)
      return true
    }

    /// The same move-once, never-overwrite rule as `SettingsSelectionStore`.
    private static func migrate(_ legacyKeys: [String], to key: String, in defaults: UserDefaults) {
      let alreadyRecorded = defaults.object(forKey: key) != nil
      var moved = false
      for legacy in legacyKeys {
        guard defaults.object(forKey: legacy) != nil else { continue }
        if !alreadyRecorded, !moved {
          defaults.set(defaults.bool(forKey: legacy), forKey: key)
          moved = true
        }
        defaults.removeObject(forKey: legacy)
      }
    }
  }
#endif
