#if os(macOS)
  import SupportKit
  import SwiftUI

  /// The Help menu, standardised.
  ///
  /// Four of the nine apps already hand-rolled almost exactly this — a
  /// `CommandGroup(replacing: .help)` holding a `Button` on ⌘/ that posts a
  /// `NotificationCenter` message, a `Divider`, then outbound `Link`s. This is
  /// that block, with the links no longer written out per app.
  ///
  /// The help action stays a closure rather than becoming part of the package.
  /// Every app already routes ⌘/ its own way — a notification, a `@State` flag,
  /// an `openWindow` — and replacing that plumbing is a different project that
  /// would have to land in nine repos before any of them got a feedback link.
  public struct SupportCommands: Commands {
    private let app: SupportApp
    private let showHelp: (() -> Void)?
    private let preferIssueTracker: Bool

    /// - Parameters:
    ///   - app: the app's support identity.
    ///   - preferIssueTracker: put the public tracker above the feedback form.
    ///     True for the developer-facing apps, where a public, searchable,
    ///     subscribable issue is a feature. False where a GitHub account is a
    ///     wall between the user and telling you what is wrong.
    ///   - showHelp: the app's existing ⌘/ action. Nil omits the item.
    public init(
      app: SupportApp,
      preferIssueTracker: Bool = false,
      showHelp: (() -> Void)? = nil
    ) {
      self.app = app
      self.showHelp = showHelp
      self.preferIssueTracker = preferIssueTracker
    }

    public var body: some Commands {
      CommandGroup(replacing: .help) {
        if let showHelp {
          Button("\(app.displayName) Help", action: showHelp)
            .keyboardShortcut("/", modifiers: .command)
          Divider()
        }
        if preferIssueTracker {
          issueLink
          feedbackLink
        } else {
          feedbackLink
          issueLink
        }
        Link("\(app.displayName) Support", destination: app.supportURL)
      }
    }

    private var feedbackLink: some View {
      Link("Send Feedback…", destination: app.feedbackURL(kind: .bug))
    }

    /// `@ViewBuilder` so the nil case contributes nothing at all — an app
    /// without a tracker gets no menu item rather than a disabled one.
    @ViewBuilder private var issueLink: some View {
      if let url = app.issueURL(kind: .bug) {
        Link("Report an Issue on GitHub", destination: url)
      }
    }
  }
#endif
