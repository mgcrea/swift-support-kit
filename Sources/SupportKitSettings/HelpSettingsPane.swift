import SupportKit
import SwiftUI

/// `SupportSettingsSection` in the `Form` it belongs in. What a pane enum's
/// `.help` case returns.
///
/// Not a contradiction of `FeedbackLink.swift`'s "there is no shared `HelpView`
/// in this package". That note is about help *content* — the bespoke sheets,
/// running to hundreds of lines, that several apps have written and that no
/// shared component could replace. This is the opposite thing: the routes OUT
/// of the app, and there is exactly one right answer for those.
///
/// It exists because a Help menu is not reachable in every app that has one.
/// The fleet's three menu bar agents are `LSUIElement`, so they have no menu
/// bar at all until a window happens to be open — which left the feedback form,
/// the tracker and the support page reachable only by accident. A pane in the
/// settings window is reachable whenever settings is, which is always.
public struct HelpSettingsPane: View {
  private let app: SupportApp
  private let preferIssueTracker: Bool
  private let includesReviewLink: Bool
  private let showsHelp: (() -> Void)?

  /// - Parameters:
  ///   - preferIssueTracker: put the public tracker above the feedback form.
  ///     The same flag `SupportCommands` and `SupportSettingsSection` take, and
  ///     for the same reason — an app must not answer this question one way in
  ///     its Help menu and the other way in its settings.
  ///   - includesReviewLink: show "Rate <App>". Renders nothing anyway when the
  ///     app has no `appStoreID`, which is the case for every app that ships
  ///     outside the store.
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
    Form {
      SupportSettingsSection(
        app: app,
        preferIssueTracker: preferIssueTracker,
        includesReviewLink: includesReviewLink,
        showsHelp: showsHelp
      )
    }
    .formStyle(.grouped)
  }
}
