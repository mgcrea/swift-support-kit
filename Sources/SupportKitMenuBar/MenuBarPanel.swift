#if os(macOS)
  import AppKit
  import SupportKit
  import SwiftUI

  /// The chrome around a `MenuBarExtra(.window)` panel — header, footer, width,
  /// and the one thing none of the five apps had: a body that scrolls.
  ///
  /// The app supplies its body through `content:`, which is the `VStack` it
  /// already had. Everything around it belongs here:
  ///
  /// ```swift
  /// MenuBarPanel(
  ///     app: Support.app,
  ///     version: AppInfo.shortVersion,
  ///     onOpenApp: { MainWindowController.show() },
  ///     onShowAbout: { SettingsWindowController.show(.about) },
  ///     footer: MenuBarFooter(
  ///         routes: [
  ///             .logs { MainWindowController.show(.log) },
  ///             .settings { SettingsWindowController.show() },
  ///         ],
  ///         whatsNew: Changelog.hasUnseen
  ///             ? .init(version: AppInfo.version) { SettingsWindowController.show(.whatsNew) }
  ///             : nil
  ///     )
  /// ) {
  ///     gatewayStatus
  ///     Divider()
  ///     ServersSection(activity: activity)
  /// }
  /// ```
  ///
  /// ## Why the body scrolls and the chrome does not
  ///
  /// Not one of the five panels had a `ScrollView`. Each bounded its height by
  /// hand-capping one list — `visible = 4`, `visibleSessions = 3` — and in two
  /// of them the *other* list was uncapped and could run off the screen:
  /// cupertino iterated twelve surfaces beside a connections list capped at four
  /// *precisely because there is no scroll view*, and armada iterated however
  /// many `~/.claude-<name>` folders exist at ~100pt each.
  ///
  /// So the cap belongs here, where it is one decision instead of five, and it
  /// applies to the body alone. A panel that scrolled as a whole would take the
  /// Quit button with it, which is worse than clipping: a summary you cannot
  /// dismiss from.
  ///
  /// What this does **not** do is make the per-app caps redundant. Those stay,
  /// and they should — "show four servers and then a link" is an editorial claim
  /// about what a summary is for. This only stops that claim from being the one
  /// thing between the app and a panel taller than the display.
  @available(macOS 26, *)
  public struct MenuBarPanel<Content: View, Accessory: View>: View {
    private let app: SupportApp
    private let version: String
    private let systemImage: String?
    private let subtitle: LocalizedStringKey?
    private let metrics: MenuBarMetrics
    private let onOpenApp: () -> Void
    private let onShowAbout: (() -> Void)?
    private let footer: MenuBarFooter
    private let accessory: Accessory
    private let content: Content

    /// Nil until the first layout pass; see `scrollingBody`.
    @State private var contentHeight: CGFloat?

    /// - Parameters:
    ///   - app: supplies `displayName`, which names the panel, the primary
    ///     button and both tooltips — so the button whose width was measured
    ///     truncating cannot disagree with the panel it was measured in.
    ///   - version: stays the app's own string. Armada suffixes `-dev`, bastion
    ///     ` (debug)`, and both pin it for a screenshot run; a version derived
    ///     here would quietly undo all three.
    ///   - systemImage: a leading glyph, for the two panels that have one.
    ///   - subtitle: a second header line. dev-pulse's status line.
    ///   - onOpenApp: called by the title **and** the primary button. One
    ///     closure, because they are one action — armada noticed that first.
    ///   - onShowAbout: makes the version clickable. Pass nil while an app has
    ///     no About pane; the version then renders as plain text rather than as
    ///     a button that goes nowhere.
    ///   - accessory: trailing header content. almanac's collecting spinner.
    public init(
      app: SupportApp,
      version: String,
      systemImage: String? = nil,
      subtitle: LocalizedStringKey? = nil,
      metrics: MenuBarMetrics = .default,
      onOpenApp: @escaping () -> Void,
      onShowAbout: (() -> Void)? = nil,
      footer: MenuBarFooter,
      @ViewBuilder accessory: () -> Accessory,
      @ViewBuilder content: () -> Content
    ) {
      self.app = app
      self.version = version
      self.systemImage = systemImage
      self.subtitle = subtitle
      self.metrics = metrics
      self.onOpenApp = onOpenApp
      self.onShowAbout = onShowAbout
      self.footer = footer
      self.accessory = accessory()
      self.content = content()
    }

    public var body: some View {
      // spacing 0, with each band paying for its own gap. The single spaced
      // `VStack` every app had cannot work once the middle band scrolls — and
      // it is also what produced bastion's phantom gap, where a notice that
      // rendered `EmptyView` still took a full 12pt slot for every licensed
      // user, doubling the space under the header.
      VStack(alignment: .leading, spacing: 0) {
        header
          .padding(.horizontal, metrics.padding)
          .padding(.top, metrics.padding)
          .padding(.bottom, metrics.spacing)

        scrollingBody

        footerView
          .padding(.horizontal, metrics.padding)
          .padding(.top, metrics.spacing)
          .padding(.bottom, metrics.padding)
      }
      .frame(width: metrics.width)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("menubar.panel")
    }

    // MARK: - Header

    private var header: some View {
      VStack(alignment: .leading, spacing: 2) {
        // armada's header, which is the one the fleet settled on.
        //
        // Three apps showed a version here and they did not agree: bastion and
        // cupertino set it immediately after the name as a baseline-aligned
        // suffix, armada pushed it to the trailing edge. Both had a written
        // reason and bastion's and cupertino's was the same sentence twice —
        // "the one piece of horizontal space that costs nothing", an argument
        // about a panel too narrow to spend width on. That argument is about
        // where a version may *fit*, not about where it belongs, and the panel
        // is now a fixed 320 for everyone: the space is there either way.
        //
        // What settles it is what the two ends of this row are for. The name
        // opens the app and the version opens About — two destinations, not a
        // heading with a footnote — and a suffix reads as the latter. Pinned
        // right, each end is one target, which is also why the version can be a
        // button without looking like a typo in the title.
        //
        // Centre-aligned rather than baseline: a baseline shared across a
        // spacer is not a visible relationship, and it is the wrong one to
        // preserve once a glyph or a spinner can sit in the same row.
        HStack(spacing: 6) {
          if let systemImage {
            Image(systemName: systemImage)
              .foregroundStyle(.tint)
              // The glyph restates the name beside it. Announcing it twice is
              // noise, and it carries nothing the title does not.
              .accessibilityHidden(true)
          }

          // The title opens the window, same as the primary button below it.
          //
          // No link colour: this is the one piece of plain text in the panel,
          // and colouring it would make it look like the only thing worth
          // reading. The pointer and the tooltip are the affordance instead,
          // which is how a Finder path bar says the same thing. (armada's
          // reasoning, kept verbatim because it is the right one.)
          Button(action: onOpenApp) {
            Text(app.displayName).font(.headline)
          }
          .buttonStyle(.plain)
          .pointerStyle(.link)
          .help(openTitle)
          .accessibilityLabel(openTitle)
          .accessibilityIdentifier("menubar.title")

          Spacer()

          // Before the version rather than after it, so the version stays the
          // row's fixed right edge: almanac's accessory is a spinner that comes
          // and goes, and a version that slid sideways whenever it appeared
          // would be the one moving part in an otherwise static header.
          accessory

          versionLabel
        }

        if let subtitle {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }

    /// Pinned to the trailing edge, and clickable when there is an About pane to
    /// reach. See the header for why it sits there rather than beside the name.
    ///
    /// It opens **About**, not What's New. A version string is the build's
    /// identity, and what continues that question is the build number, the OS,
    /// the machine and the copy-diagnostics button — the things you want with a
    /// bug report open. What the build *changed* is a different question, asked
    /// at a different moment, and it already has the one-shot row in the footer.
    @ViewBuilder private var versionLabel: some View {
      if let onShowAbout {
        Button(action: onShowAbout) {
          Text(version).font(.caption).foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help(aboutTitle)
        .accessibilityLabel(aboutTitle)
        .accessibilityIdentifier("menubar.version")
      } else {
        Text(version)
          .font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("menubar.version")
      }
    }

    // MARK: - Body

    /// Plain when it fits, scrolling when it does not — decided from a measured
    /// height rather than from the proposal.
    ///
    /// Both obvious spellings of this empty the panel, and they empty it the
    /// same way for the same reason: **a `MenuBarExtra` panel proposes almost no
    /// height.** The window sizes itself to its content, so on the pass that
    /// matters the middle band is offered nothing, and anything flexible in the
    /// vertical axis takes the offer.
    ///
    /// `ViewThatFits` went first. It picks the first child that fits the
    /// proposal *it* is given, the cap has to sit outside it, and against a
    /// proposal of nothing neither child fits — at which point it does not fall
    /// back to the roomiest child, it takes the **last** one. That is the
    /// `ScrollView`, laid out at no useful height. An unconditional
    /// `ScrollView` under `.frame(maxHeight:)` fails identically: a scroll view
    /// has no intrinsic height, so it accepts the nothing it is offered.
    ///
    /// Measured in bastion, the first spelling left the rows drawing forty
    /// points below the panel's own bottom edge and the second clipped them
    /// away entirely — a panel showing its header and its footer with nothing
    /// between them, which reads as an app with no content rather than as a
    /// broken layout.
    ///
    /// So the height is measured and the decision made from it. `fixedSize` is
    /// what actually holds the panel open: it makes the band report its
    /// content's ideal height and refuse to shrink to the proposal. The scroll
    /// view appears only once the content genuinely outgrows the screen, where
    /// it is given a **definite** height and so has something to accept.
    ///
    /// There is no first-frame flash, which is why the test is `> cap` rather
    /// than a cap applied unconditionally: before anything is measured the panel
    /// draws its real content at its natural height, which is already the right
    /// answer for every panel that fits. Only an overflowing one switches, and
    /// once switched the measurement still reads the full content height, so it
    /// stays switched rather than oscillating.
    private var scrollingBody: some View {
      let measured =
        contentStack
        .onGeometryChange(for: CGFloat.self) { proxy in
          proxy.size.height
        } action: { height in
          contentHeight = height
        }

      return Group {
        if let contentHeight, contentHeight > metrics.bodyCap {
          ScrollView(.vertical) { measured }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: metrics.bodyCap)
        } else {
          measured.fixedSize(horizontal: false, vertical: true)
        }
      }
    }

    private var contentStack: some View {
      VStack(alignment: .leading, spacing: metrics.spacing) {
        content
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, metrics.padding)
    }

    // MARK: - Footer

    private var footerView: some View {
      VStack(alignment: .leading, spacing: metrics.spacing) {
        Divider()

        if !footer.verbs.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(footer.verbs) { verb in
              verbButton(verb)
            }
          }
          .buttonStyle(.plain)
          .labelStyle(.titleAndIcon)

          Divider()
        }

        actionRow

        if let whatsNew = footer.whatsNew {
          Divider()
          Button(localized("What's new in \(whatsNew.version)…"), action: whatsNew.run)
            .controlSize(.small)
            .accessibilityIdentifier("menubar.whatsNew")
        }
      }
    }

    /// Glass on the left, plain on the right, and the gap after the primary
    /// rather than before Quit: what opens something sits left, what you go to
    /// sits right. Only the primary is tinted, because a tinted button is a
    /// recommendation and it is the one being recommended; the glyphs beside
    /// Quit are routes, not advice.
    private var actionRow: some View {
      HStack {
        Button(action: onOpenApp) {
          openTitle
        }
        .buttonStyle(.glass)
        .keyboardShortcut("o")
        .accessibilityIdentifier("menubar.open")

        Spacer()

        ForEach(footer.routes) { route in
          routeButton(route)
        }

        // Terminate is spelled here rather than taken as a closure. All five
        // apps passed the identical `NSApplication.shared.terminate(nil)`, and a
        // parameter for it is one more thing that can differ between panels that
        // must not differ. ⌘Q is supplied for the same reason: cupertino was
        // missing both it and ⌘O from a row its own comments describe as the
        // same row the siblings have.
        Button(localized("Quit")) { NSApplication.shared.terminate(nil) }
          .keyboardShortcut("q")
          .accessibilityIdentifier("menubar.quit")
      }
      .controlSize(.small)
    }

    @ViewBuilder private func verbButton(_ verb: MenuBarAction) -> some View {
      let button = Button(action: verb.run) {
        Label {
          Text(verb.title)
        } icon: {
          if let systemImage = verb.systemImage {
            Image(systemName: systemImage)
          }
        }
      }
      .disabled(verb.isDisabled)
      .help(verb.helpText)
      .accessibilityIdentifier("menubar.verb.\(verb.id)")

      if let shortcut = verb.shortcut {
        button.keyboardShortcut(shortcut, modifiers: verb.modifiers)
      } else {
        button
      }
    }

    /// A glyph, with its name reaching VoiceOver through `accessibilityLabel`
    /// and the pointer through `help` — never through the glyph name, which is
    /// what "gearshape" announced in three shipping apps.
    @ViewBuilder private func routeButton(_ route: MenuBarAction) -> some View {
      let button = Button(action: route.run) {
        if let systemImage = route.systemImage {
          Image(systemName: systemImage)
        } else {
          Text(route.title)
        }
      }
      .disabled(route.isDisabled)
      .help(route.helpText)
      .accessibilityLabel(Text(route.title))
      .accessibilityIdentifier("menubar.route.\(route.id)")

      if let shortcut = route.shortcut {
        button.keyboardShortcut(shortcut, modifiers: route.modifiers)
      } else {
        button
      }
    }

    // MARK: - Strings

    private var openTitle: Text { Text(localized("Open \(app.displayName)")) }
    private var aboutTitle: Text { Text(localized("About \(app.displayName)")) }
  }

  // MARK: - The common case

  @available(macOS 26, *)
  extension MenuBarPanel where Accessory == EmptyView {
    /// Four of the five panels have nothing trailing in the header.
    public init(
      app: SupportApp,
      version: String,
      systemImage: String? = nil,
      subtitle: LocalizedStringKey? = nil,
      metrics: MenuBarMetrics = .default,
      onOpenApp: @escaping () -> Void,
      onShowAbout: (() -> Void)? = nil,
      footer: MenuBarFooter,
      @ViewBuilder content: () -> Content
    ) {
      self.init(
        app: app,
        version: version,
        systemImage: systemImage,
        subtitle: subtitle,
        metrics: metrics,
        onOpenApp: onOpenApp,
        onShowAbout: onShowAbout,
        footer: footer,
        accessory: { EmptyView() },
        content: content
      )
    }
  }
#endif
