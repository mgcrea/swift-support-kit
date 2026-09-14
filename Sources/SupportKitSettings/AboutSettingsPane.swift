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
  private let showsIdentifier: Bool
  private let debugNotice: LocalizedStringKey?
  private let copySummary: String?
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
  ///   - showsIdentifier: add the running bundle identifier as a row. Off by
  ///     default because it is noise in an app that ships one bundle id; worth
  ///     turning on for one that also ships a `.debug` build somebody might be
  ///     staring at without realising it.
  ///   - debugNotice: shown, in orange, ONLY when the running bundle id ends in
  ///     `.debug` — so passing it costs a shipped build nothing. Nil renders a
  ///     generic sentence; pass a string to name this app's own consequences,
  ///     which is usually the separate stored data a second bundle id implies.
  ///   - copySummary: what the copy button puts on the pasteboard. Nil uses
  ///     `diagnostics.bugReportSummary(for:)`, which deliberately carries the
  ///     same four facts as the feedback URL and no more — see the rule stated
  ///     on that method. An app that overrides this is taking ownership of that
  ///     decision, and should only widen it to facts about the BUILD (a commit,
  ///     a signing identity), never about the person running it.
  ///   - includesSupport: append `SupportSettingsSection`. Leave it on unless
  ///     the app puts those rows somewhere else in the same window — an app with
  ///     a dedicated Help pane wants this off, or the rows appear twice.
  ///   - extraRows: whatever this app has that the others do not — a debug-build
  ///     warning, a bundle identifier, a credits list. The escape hatch that
  ///     stops the component being forked.
  public init(
    app: SupportApp,
    diagnostics: Diagnostics = .current,
    showsIcon: Bool = true,
    showsIdentifier: Bool = false,
    debugNotice: LocalizedStringKey? = nil,
    copySummary: String? = nil,
    includesSupport: Bool = true,
    preferIssueTracker: Bool = false,
    showsHelp: (() -> Void)? = nil,
    @ViewBuilder extraRows: () -> Extra
  ) {
    self.app = app
    self.diagnostics = diagnostics
    self.showsIcon = showsIcon
    self.showsIdentifier = showsIdentifier
    self.debugNotice = debugNotice
    self.copySummary = copySummary
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
      LabeledContent(localized("System"), value: diagnostics.osVersion)
        .textSelection(.enabled)
      LabeledContent(localized("Model"), value: diagnostics.hardware)
        .textSelection(.enabled)
      if showsIdentifier {
        LabeledContent(localized("Identifier"), value: RunningBundle.identifier)
          .textSelection(.enabled)
      }
      if RunningBundle.isDebug {
        debugNoticeRow
      }
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
          SupportClipboard.copy(copySummary ?? diagnostics.bugReportSummary(for: app))
          copied = true
        } label: {
          Image(systemName: copied ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .help(localized("Copy version and system details for a bug report"))
        .accessibilityLabel(localized("Copy version and system details for a bug report"))
      }
    } label: {
      Text(localized("Version"))
    }
    .task(id: copied) {
      guard copied else { return }
      try? await Task.sleep(for: .seconds(2))
      copied = false
    }
  }

  /// Orange, and only on a `.debug` bundle.
  ///
  /// A second bundle identifier means a second everything — its own defaults,
  /// its own Keychain items, its own stored files — and two menu bar icons that
  /// look identical while holding different credentials is otherwise a
  /// confusing afternoon. One app in the fleet wrote this warning for itself
  /// first; every app that ships a debug build alongside has the same problem.
  private var debugNoticeRow: some View {
    Group {
      if let debugNotice {
        Text(debugNotice)
      } else {
        Text(RunningBundle.genericDebugNotice)
      }
    }
    .font(.caption)
    .foregroundStyle(.orange)
    .fixedSize(horizontal: false, vertical: true)
  }
}

/// Bundle facts, read once.
///
/// A caseless enum rather than statics on `AboutSettingsSection`, which is
/// generic over its extra rows — and a generic type cannot hold a static stored
/// property, so the obvious spelling does not compile.
private enum RunningBundle {
  /// This package's sentence, so it comes from this package's catalog — a
  /// `debugNotice` the app passes is a key into the app's own. Computed rather
  /// than stored so the lookup runs when the row is drawn, not when the enum is
  /// first touched.
  static var genericDebugNotice: String {
    localized(
      "A debug build. It has its own bundle identifier, and therefore its own settings and its own stored data."
    )
  }

  /// The identifier cannot change while the process runs.
  static let identifier = Bundle.main.bundleIdentifier ?? "—"

  /// The `.debug` suffix is the fleet's convention for the sibling bundle id,
  /// and it is a property of the RUNNING bundle rather than of the compile —
  /// `#if DEBUG` would be wrong here, because a Release build installed under
  /// the debug identifier is exactly the case worth warning about.
  static let isDebug = identifier.hasSuffix(".debug")
}

extension AboutSettingsSection where Extra == EmptyView {
  public init(
    app: SupportApp,
    diagnostics: Diagnostics = .current,
    showsIcon: Bool = true,
    showsIdentifier: Bool = false,
    debugNotice: LocalizedStringKey? = nil,
    copySummary: String? = nil,
    includesSupport: Bool = true,
    preferIssueTracker: Bool = false,
    showsHelp: (() -> Void)? = nil
  ) {
    self.init(
      app: app,
      diagnostics: diagnostics,
      showsIcon: showsIcon,
      showsIdentifier: showsIdentifier,
      debugNotice: debugNotice,
      copySummary: copySummary,
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
    showsIdentifier: Bool = false,
    debugNotice: LocalizedStringKey? = nil,
    copySummary: String? = nil,
    includesSupport: Bool = true,
    preferIssueTracker: Bool = false,
    showsHelp: (() -> Void)? = nil,
    @ViewBuilder extraRows: () -> Extra
  ) {
    section = AboutSettingsSection(
      app: app,
      diagnostics: diagnostics,
      showsIcon: showsIcon,
      showsIdentifier: showsIdentifier,
      debugNotice: debugNotice,
      copySummary: copySummary,
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
    showsIdentifier: Bool = false,
    debugNotice: LocalizedStringKey? = nil,
    copySummary: String? = nil,
    includesSupport: Bool = true,
    preferIssueTracker: Bool = false,
    showsHelp: (() -> Void)? = nil
  ) {
    self.init(
      app: app,
      diagnostics: diagnostics,
      showsIcon: showsIcon,
      showsIdentifier: showsIdentifier,
      debugNotice: debugNotice,
      copySummary: copySummary,
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
