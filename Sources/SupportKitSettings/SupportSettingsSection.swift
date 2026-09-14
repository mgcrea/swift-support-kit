import SupportKit
import SupportKitUI
import SwiftUI

/// The routes out of the app, for the platform that has no Help menu.
///
/// `SupportCommands` reaches the Mac and the iPad, the two places with a menu
/// bar. A phone has no Help menu to put it in, so without this section the
/// feedback form, the tracker and the support page are reachable from nowhere on
/// an iPhone. Six of the twelve apps have an iOS surface.
///
/// So this is not decoration on the About pane. It is the thing that makes an
/// About pane load-bearing rather than a version readout.
public struct SupportSettingsSection: View {
  private let app: SupportApp
  private let preferIssueTracker: Bool
  private let includesReviewLink: Bool
  private let showsHelp: (() -> Void)?

  /// - Parameters:
  ///   - preferIssueTracker: put the public tracker above the feedback form.
  ///     The same flag `SupportCommands` takes, deliberately — an app must not
  ///     be able to answer this question one way in its Help menu and the other
  ///     way in its settings.
  ///   - includesReviewLink: show "Rate <App>". Renders nothing anyway when the
  ///     app has no `appStoreID`.
  ///   - showsHelp: the app's existing ⌘/ action. Nil omits the row. Pass the
  ///     identical closure here and to `SupportCommands`, so the two cannot
  ///     open different help.
  public init(
    app: SupportApp,
    preferIssueTracker: Bool = false,
    includesReviewLink: Bool = true,
    showsHelp: (() -> Void)? = nil
  ) {
    self.app = app
    self.preferIssueTracker = preferIssueTracker
    self.includesReviewLink = includesReviewLink
    self.showsHelp = showsHelp
  }

  public var body: some View {
    Section {
      if let showsHelp {
        Button(action: showsHelp) {
          Label(localized("\(app.displayName) Help"), systemImage: "questionmark.circle")
        }
      }
      if preferIssueTracker {
        IssueTrackerLink(app: app)
        FeedbackLink(app: app)
      } else {
        FeedbackLink(app: app)
        IssueTrackerLink(app: app)
      }
      Link(destination: app.supportURL) {
        Label(localized("\(app.displayName) Support"), systemImage: "lifepreserver")
      }
      if includesReviewLink, let review = app.appStoreReviewURL {
        Link(destination: review) {
          Label(localized("Rate \(app.displayName)"), systemImage: "star")
        }
      }
    }
  }
}
