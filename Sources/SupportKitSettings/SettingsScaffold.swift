import SwiftUI

/// Where a settings surface is being drawn.
public enum SettingsPresentation: Sendable {
  /// A macOS window — a `Settings` scene, or one built by hand for an
  /// `LSUIElement` app. The sidebar is always visible.
  case window

  /// iOS, at the root of its own navigation: a sheet, or a tab. The split view
  /// collapses to a list that pushes, which is the shape the apps that
  /// hand-rolled this already had.
  case standalone

  /// iOS, already inside somebody else's `NavigationStack`.
  ///
  /// A `NavigationSplitView` cannot go here. Nested in a stack destination it
  /// yields two back buttons, a title that does not push, and a collapsed
  /// split view fighting the outer stack for the navigation bar. This mode
  /// draws the same rows, the same identifiers and the same panes as a plain
  /// `List`, and lets the outer stack keep doing the navigating.
  ///
  /// Prefer restructuring the host to present settings as a sheet — that makes
  /// every surface in the app the same shape. This is the escape hatch for
  /// where that is genuinely too invasive.
  case embedded

  /// `.window` on macOS, `.standalone` everywhere else.
  case automatic
}

/// The settings sidebar, the selection, and the identifiers — once.
///
/// The app supplies its pane bodies through `detail:`; that closure is
/// character-for-character the `content(for:)` most of the fleet already has.
/// Everything around it belongs here:
///
/// ```swift
/// SettingsScaffold(selection: Support.settings, staged: DemoSeed.stagedPane) { pane in
///     switch pane {
///     case .general: GeneralPane()
///     case .licence: LicencePane()
///     case .about: AboutSettingsPane(app: Support.app)
///     }
/// }
/// .settingsWindowSize(CGSize(width: 720, height: 520))
/// ```
public struct SettingsScaffold<Pane: SettingsPane, Detail: View>: View {
  @AppStorage private var storedRawValue: String

  private let staged: Pane?
  private let presentation: SettingsPresentation
  private let metrics: SettingsSidebarMetrics
  private let rootTitle: LocalizedStringKey
  private let onPaneChange: ((Pane) -> Void)?
  private let embeddedPath: Binding<[Pane]>?
  private let detail: (Pane) -> Detail

  /// - Parameters:
  ///   - selection: the app's persisted pane selection.
  ///   - staged: a pane to force, for a screenshot run. See `resolved`.
  ///   - presentation: defaults to `.automatic`.
  ///   - metrics: sidebar width. Defaults to the fleet's widest.
  ///   - rootTitle: the navigation title in the collapsed layouts. The window
  ///     layouts do not use it — the window already has a title. The default is
  ///     this package's "Settings", already translated from its own catalog and
  ///     handed over as a key: a key the app's catalog does not hold draws
  ///     itself, so "Réglages" arrives as "Réglages". A literal default would be
  ///     looked up in the app's catalog instead, and stay English in an app that
  ///     happens not to carry that key.
  ///   - embeddedPath: required by `.embedded` and ignored otherwise, so a
  ///     staged run can push without a driver to tap.
  ///   - onPaneChange: called after a real selection. dev-pulse asserts on this
  ///     during a capture, having learned that a settings window which came up
  ///     on the wrong pane is a valid, correctly-sized, perfectly still
  ///     photograph that every automated gate passes.
  ///   - detail: the app's pane bodies.
  public init(
    selection: SettingsSelection<Pane>,
    staged: Pane? = nil,
    presentation: SettingsPresentation = .automatic,
    metrics: SettingsSidebarMetrics = .default,
    rootTitle: LocalizedStringKey = LocalizedStringKey(localized("Settings")),
    embeddedPath: Binding<[Pane]>? = nil,
    onPaneChange: ((Pane) -> Void)? = nil,
    @ViewBuilder detail: @escaping (Pane) -> Detail
  ) {
    _storedRawValue = AppStorage(
      wrappedValue: Pane.defaultPane.rawValue, selection.storageKey)
    self.staged = staged
    self.presentation = presentation
    self.metrics = metrics
    self.rootTitle = rootTitle
    self.embeddedPath = embeddedPath
    self.onPaneChange = onPaneChange
    self.detail = detail
  }

  /// The pane actually being drawn.
  ///
  /// `staged` wins outright. A capture run must not depend on what the
  /// developer last had open, and — see `selectionBinding` — must not change it
  /// either.
  private var resolved: Pane {
    staged ?? Pane.resolving(storedRawValue)
  }

  /// Reading is `resolved`; writing has two guards, and both are load-bearing.
  ///
  /// **A `nil` write is dropped rather than stored.** `List` hands `nil` back on
  /// its way up, before the tagged rows have registered, so folding it into a
  /// real pane overwrites whatever was just selected a frame later. It cost a
  /// staged screenshot that opened on the wrong pane having asked for the right
  /// one, and only sometimes, which is the worst way to find out.
  ///
  /// **Under `staged`, every write is dropped.** A capture run that persists a
  /// selection leaves the developer's settings pointing wherever the last
  /// screenshot needed. The sibling bug has already been seen in this fleet
  /// with window frames: a capture run wrote the pinned size back out under the
  /// key the real window reads, and left every window that size.
  private var selectionBinding: Binding<Pane?> {
    Binding(
      get: { resolved },
      set: { newValue in
        guard staged == nil, let newValue else { return }
        storedRawValue = newValue.rawValue
        onPaneChange?(newValue)
      }
    )
  }

  private var effectivePresentation: SettingsPresentation {
    guard presentation == .automatic else { return presentation }
    #if os(macOS)
      return .window
    #else
      return .standalone
    #endif
  }

  public var body: some View {
    Group {
      switch effectivePresentation {
      case .embedded:
        embeddedList
      case .window, .standalone, .automatic:
        splitView
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("settings.root")
  }

  // MARK: - The sidebar layouts

  private var splitView: some View {
    NavigationSplitView {
      sidebar
    } detail: {
      detailColumn
    }
  }

  private var sidebar: some View {
    List(selection: selectionBinding) {
      paneRows(pushes: false)
    }
    .navigationSplitViewColumnWidth(
      min: metrics.minWidth, ideal: metrics.idealWidth, max: metrics.maxWidth
    )
    #if os(macOS)
      // The sidebar *is* the navigation here. Collapsing it strands a pane
      // with no way back to any other one.
      .toolbar(removing: .sidebarToggle)
    #else
      .navigationTitle(rootTitle)
    #endif
  }

  /// - Parameter pushes: `true` in `.embedded`, where the row must navigate
  ///   rather than select. Everywhere else the split view owns the selection
  ///   and a `NavigationLink` here would nest a second navigation.
  @ViewBuilder private func paneRows(pushes: Bool) -> some View {
    // One occupied group draws no `Section` wrapper: an app with a single
    // group must not get a divider between one thing and one thing.
    if Pane.occupiedGroups.count <= 1 {
      rows(in: Pane.occupiedGroups.first ?? .configuration, pushes: pushes)
    } else {
      ForEach(Pane.occupiedGroups, id: \.self) { group in
        Section {
          rows(in: group, pushes: pushes)
        }
      }
    }
  }

  /// The two branches are written out rather than sharing a `Group`, and that is
  /// not a style choice.
  ///
  /// `.tag` sets a view *trait*, and `List` reads traits from the row view it is
  /// handed — not from a descendant. Set inside a `Group` that is then modified,
  /// the tag belongs to the `Label` and the row exposes nothing, so the sidebar
  /// draws correctly, highlights correctly, and selects nothing at all. What
  /// makes it hard to spot is that `Group` *does* forward the modifiers applied
  /// to it down to each child, so `.accessibilityIdentifier` lands exactly where
  /// it should and the accessibility tree looks right while the window is inert.
  /// `.tag` has to be the outermost modifier on the row.
  @ViewBuilder private func rows(in group: SettingsPaneGroup, pushes: Bool) -> some View {
    if pushes {
      ForEach(Pane.panes(in: group)) { pane in
        NavigationLink(value: pane) {
          Label(pane.title, systemImage: pane.systemImage)
        }
        .badge(pane.badge)
        .accessibilityIdentifier("settings.pane.\(pane.rawValue)")
      }
    } else {
      ForEach(Pane.panes(in: group)) { pane in
        Label(pane.title, systemImage: pane.systemImage)
          .badge(pane.badge)
          .accessibilityIdentifier("settings.pane.\(pane.rawValue)")
          .tag(pane)
      }
    }
  }

  private var detailColumn: some View {
    VStack(alignment: .leading, spacing: 0) {
      #if os(macOS)
        // The heading is drawn in the content, not through
        // `.navigationTitle`. The window keeps its own name — "Cupertino
        // Settings" in ⌘-Tab and the Window menu — while the page still
        // says which page it is. No `ScrollView` around this: every pane
        // is a grouped `Form`, which scrolls itself, so the heading stays
        // pinned above the cards rather than sliding away with them.
        Text(resolved.title)
          .font(.title2)
          .fontWeight(.semibold)
          .padding(.horizontal, 20)
          .padding(.top, 16)
      #endif
      detail(resolved)
    }
    #if !os(macOS)
      .navigationTitle(resolved.title)
    #endif
  }

  // MARK: - Embedded

  /// A plain list that pushes, for a host that already owns a stack.
  ///
  /// Value-based links rather than view-based ones, and the path is the host's:
  /// a `NavigationPath` is the only way to arrive somewhere without a driver
  /// tapping its way there, and on a staged relaunch there is no driver.
  @ViewBuilder private var embeddedList: some View {
    List {
      paneRows(pushes: true)
    }
    .navigationTitle(rootTitle)
    .navigationDestination(for: Pane.self) { pane in
      detail(pane)
        .navigationTitle(pane.title)
    }
    .task {
      // A staged run has no driver to tap, so the push is made here. Only
      // onto an empty path: a capture must not fight a person who has
      // already navigated, and must not push a second copy of the pane it
      // is being relaunched to photograph.
      guard let staged, let embeddedPath, embeddedPath.wrappedValue.isEmpty else { return }
      embeddedPath.wrappedValue = [staged]
    }
  }
}
