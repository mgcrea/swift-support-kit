import SupportKit
import SupportKitUI
import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

/// The version, the machine, and the way out — as rows.
///
/// The section is the real component and the pane below is a thin wrapper on it,
/// because half the fleet already has a `Form` to drop these into: a Credits tab,
/// an About tab, a General tab, and every single-form iPhone screen. Forcing
/// those to nest a `Form` inside a `Form` is how a settings card grows a hundred
/// points of nothing, which one app in this fleet has already hit twice.
public struct AboutSettingsSection<Extra: View>: View {
  private let app: SupportApp
  private let diagnostics: Diagnostics
  private let showsIcon: Bool
  private let includesSupport: Bool
  private let preferIssueTracker: Bool
  private let showsHelp: (() -> Void)?
  private let extraRows: Extra

  @State private var copied = false

  /// - Parameters:
  ///   - diagnostics: a parameter rather than always `.current`, and this is
  ///     not over-generalisation. A real version number renders into every
  ///     settings screenshot, which churns the golden gate on every release and
  ///     publishes a version to a marketing site before the listing showing it
  ///     has caught up. One app in the fleet already pins its version under
  ///     demo mode for exactly that reason; this is the hook it pins through.
  ///   - showsIcon: draw the app icon above the rows. False for a narrow pane.
  ///   - includesSupport: append `SupportSettingsSection`. Leave it on unless
  ///     the app puts those rows somewhere else in the same window.
  ///   - extraRows: whatever this app has that the others do not — a debug-build
  ///     warning, a bundle identifier, a credits list. The escape hatch that
  ///     stops the component being forked.
  public init(
    app: SupportApp,
    diagnostics: Diagnostics = .current,
    showsIcon: Bool = true,
    includesSupport: Bool = true,
    preferIssueTracker: Bool = false,
    showsHelp: (() -> Void)? = nil,
    @ViewBuilder extraRows: () -> Extra
  ) {
    self.app = app
    self.diagnostics = diagnostics
    self.showsIcon = showsIcon
    self.includesSupport = includesSupport
    self.preferIssueTracker = preferIssueTracker
    self.showsHelp = showsHelp
    self.extraRows = extraRows()
  }

  public var body: some View {
    Section {
      if showsIcon {
        identityRow
      }
      versionRow
      LabeledContent("System", value: diagnostics.osVersion)
        .textSelection(.enabled)
      LabeledContent("Model", value: diagnostics.hardware)
        .textSelection(.enabled)
      extraRows
    }

    if includesSupport {
      SupportSettingsSection(
        app: app,
        preferIssueTracker: preferIssueTracker,
        showsHelp: showsHelp
      )
    }
  }

  private var identityRow: some View {
    HStack(spacing: 12) {
      AppIconImage()
        .frame(width: 48, height: 48)
      Text(app.displayName)
        .font(.headline)
    }
    .padding(.vertical, 2)
  }

  /// Version and build together, with the copy button on the same row.
  ///
  /// Not a `Button("Copy")` of its own: an affordance that only matters when
  /// something has gone wrong should not take a row away from the things that
  /// matter when nothing has. The glyph swap is the whole confirmation — the
  /// same pattern already shipping in four places in one of the consuming apps.
  private var versionRow: some View {
    LabeledContent {
      HStack(spacing: 8) {
        Text(diagnostics.appVersion)
          .textSelection(.enabled)
        Button {
          SupportClipboard.copy(diagnostics.bugReportSummary(for: app))
          copied = true
        } label: {
          Image(systemName: copied ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .help("Copy version and system details for a bug report")
        .accessibilityLabel("Copy version and system details for a bug report")
      }
    } label: {
      Text("Version")
    }
    .task(id: copied) {
      guard copied else { return }
      try? await Task.sleep(for: .seconds(2))
      copied = false
    }
  }
}

extension AboutSettingsSection where Extra == EmptyView {
  public init(
    app: SupportApp,
    diagnostics: Diagnostics = .current,
    showsIcon: Bool = true,
    includesSupport: Bool = true,
    preferIssueTracker: Bool = false,
    showsHelp: (() -> Void)? = nil
  ) {
    self.init(
      app: app,
      diagnostics: diagnostics,
      showsIcon: showsIcon,
      includesSupport: includesSupport,
      preferIssueTracker: preferIssueTracker,
      showsHelp: showsHelp,
      extraRows: { EmptyView() }
    )
  }
}

/// `AboutSettingsSection` in the `Form` it belongs in. What a pane enum's
/// `.about` case returns.
public struct AboutSettingsPane<Extra: View>: View {
  private let section: AboutSettingsSection<Extra>

  public init(
    app: SupportApp,
    diagnostics: Diagnostics = .current,
    showsIcon: Bool = true,
    includesSupport: Bool = true,
    preferIssueTracker: Bool = false,
    showsHelp: (() -> Void)? = nil,
    @ViewBuilder extraRows: () -> Extra
  ) {
    section = AboutSettingsSection(
      app: app,
      diagnostics: diagnostics,
      showsIcon: showsIcon,
      includesSupport: includesSupport,
      preferIssueTracker: preferIssueTracker,
      showsHelp: showsHelp,
      extraRows: extraRows
    )
  }

  public var body: some View {
    Form {
      section
    }
    .formStyle(.grouped)
  }
}

extension AboutSettingsPane where Extra == EmptyView {
  public init(
    app: SupportApp,
    diagnostics: Diagnostics = .current,
    showsIcon: Bool = true,
    includesSupport: Bool = true,
    preferIssueTracker: Bool = false,
    showsHelp: (() -> Void)? = nil
  ) {
    self.init(
      app: app,
      diagnostics: diagnostics,
      showsIcon: showsIcon,
      includesSupport: includesSupport,
      preferIssueTracker: preferIssueTracker,
      showsHelp: showsHelp,
      extraRows: { EmptyView() }
    )
  }
}

/// The running app's own icon.
///
/// Drawn rather than named, because an app's icon has no asset name that is
/// reliably the same across the fleet. One app in this fleet falls back to a
/// hand-picked SF Symbol on iOS today, which is a glyph that is *not* the app's
/// icon and that will drift from it the next time the icon changes.
///
/// Renders nothing when no icon can be found, so a Form row does not reserve
/// space for an image that is not coming.
struct AppIconImage: View {
  var body: some View {
    #if os(macOS)
      Image(nsImage: NSApplication.shared.applicationIconImage)
        .resizable()
        .scaledToFit()
    #else
      if let icon = Self.iOSIcon {
        Image(uiImage: icon)
          .resizable()
          .scaledToFit()
          .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      }
    #endif
  }

  #if !os(macOS)
    /// The last entry of `CFBundleIconFiles` is the largest one, which is the
    /// one worth scaling down. There is no `UIApplication` API for this — the
    /// icon has to be read back out of the bundle that declared it.
    static var iOSIcon: UIImage? {
      guard
        let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
        let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
        let files = primary["CFBundleIconFiles"] as? [String],
        let name = files.last
      else { return nil }
      return UIImage(named: name)
    }
  #endif
}
