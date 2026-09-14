#if os(macOS)
  import AppKit
  import ServiceManagement
  import SwiftUI

  /// The launch-at-login row, as the first `Section` of an app's General pane.
  ///
  /// First, and the same in every app that has one. It is the one setting
  /// everybody who installs a menu bar app decides on the day they install it,
  /// and armada, bastion and cupertino had drawn it three ways: a different
  /// label, a different place on the page, and errors in two different spots —
  /// bastion not at all. Owning the whole `Section`, header included, is what
  /// stops that from drifting again.
  ///
  /// What it shows is what the service reports, never what was last asked for.
  /// Beyond the checkbox it says the two things the service can be quietly
  /// holding: that macOS is waiting on the user's approval, and that this copy
  /// is somewhere a login item cannot be left.
  public struct LaunchAtLoginSection: View {
    private let loginItem: LoginItem
    private let detail: LocalizedStringKey?

    /// - Parameters:
    ///   - loginItem: the app's one `LoginItem`.
    ///   - detail: a line under the label saying what launching at login buys
    ///     in this app, resolved in the app's catalog. Worth passing wherever
    ///     the honest answer is "less than you would think" — cupertino and
    ///     bastion are both started on demand by a client's first call.
    public init(_ loginItem: LoginItem, detail: LocalizedStringKey? = nil) {
      self.loginItem = loginItem
      self.detail = detail
    }

    /// Through the model rather than a `@State` mirror, so a registration that
    /// did not take snaps the box back instead of leaving it ticked.
    private var isOn: Binding<Bool> {
      Binding(get: { loginItem.isEnabled }, set: { loginItem.set($0) })
    }

    public var body: some View {
      Section {
        Toggle(isOn: isOn) {
          Text(localized("Launch at login"))
          if let detail {
            Text(detail)
          }
        }
        // Turning it off stays possible from anywhere: an item registered from
        // a copy that has since been moved still launches something.
        .disabled(!loginItem.isEnabled && !loginItem.location.canRegister)
        .accessibilityIdentifier("settings.launchAtLogin")

        if loginItem.needsApproval {
          LabeledContent {
            Button(localized("Open System Settings…")) {
              SMAppService.openSystemSettingsLoginItems()
            }
          } label: {
            Text(localized("Allow it in Login Items & Extensions to launch at login."))
          }
        }

        if !loginItem.isEnabled, let note = locationNote {
          Text(note)
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
        }
      } header: {
        Text(localized("Startup"))
      } footer: {
        if let error = loginItem.lastError {
          Text(error).foregroundStyle(.red)
        }
      }
      .onAppear { loginItem.refresh() }
      // The item can be switched off in System Settings while this window is
      // open behind it, and coming back is the moment to find out.
      .onReceive(
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
      ) { _ in
        loginItem.refresh()
      }
    }

    private var locationNote: String? {
      switch loginItem.location {
      case .applications:
        nil
      case .translocated:
        localized(
          """
          macOS is running this copy from a temporary location that will be gone next time. \
          Move the app to your Applications folder and open it from there to launch it at login.
          """
        )
      case .elsewhere:
        localized(
          """
          A login item remembers where the app was, and this copy is outside an Applications \
          folder. Move it there to launch it at login.
          """
        )
      }
    }
  }
#endif
