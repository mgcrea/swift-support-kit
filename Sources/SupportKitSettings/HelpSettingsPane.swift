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
  private let intro: LocalizedStringKey?
  private let showsHelp: (() -> Void)?

  /// - Parameters:
  ///   - preferIssueTracker: put the public tracker above the feedback form.
  ///     The same flag `SupportCommands` and `SupportSettingsSection` take, and
  ///     for the same reason — an app must not answer this question one way in
  ///     its Help menu and the other way in its settings.
  ///   - includesReviewLink: show "Rate <App>". Renders nothing anyway when the
  ///     app has no `appStoreID`, which is the case for every app that ships
  ///     outside the store.
  ///   - intro: the paragraph above the links. Nil renders the standard
  ///     welcome, which is deliberately the safe claim: it invites bugs, ideas
  ///     and questions, and says what the links carry. Pass a replacement in an
  ///     app whose source is public, so it can invite a pull request too — that
  ///     sentence is NOT in the default, because it would be a false
  ///     invitation in an app whose tracker is an issues-only repository.
  ///   - showsHelp: the app's existing ⌘/ action. Nil omits the row. Pass the
  ///     identical closure here and to `SupportCommands`, so the two cannot
  ///     open different help.
  public init(
    app: SupportApp,
    preferIssueTracker: Bool = false,
    includesReviewLink: Bool = true,
    intro: LocalizedStringKey? = nil,
    showsHelp: (() -> Void)? = nil
  ) {
    self.app = app
    self.preferIssueTracker = preferIssueTracker
    self.includesReviewLink = includesReviewLink
    self.intro = intro
    self.showsHelp = showsHelp
  }

  /// Says what the two prefilled links carry, which is the question somebody
  /// asks before pressing one. `SupportApp+URLs` puts the four facts in the
  /// query string and the issue body precisely so they can be read first; this
  /// is the sentence that tells the reader to look.
  ///
  /// A `String` from this package's catalog, where `intro` is a key into the
  /// app's: the default is the package's sentence, a replacement is the app's.
  private var standardIntro: String {
    localized(
      """
      Bugs, ideas and questions are all welcome, and none of them is a bother. \
      The feedback form and the issue template arrive with your version, macOS, \
      Mac model and language already filled in, where you can read them before \
      anything is sent.
      """
    )
  }

  public var body: some View {
    Form {
      Section {
        Group {
          if let intro {
            Text(intro)
          } else {
            Text(standardIntro)
          }
        }
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }

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
