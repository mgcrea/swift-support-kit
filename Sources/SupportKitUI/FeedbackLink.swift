import SupportKit
import SwiftUI

/// A link to the feedback form, for placing inside an app's own help sheet.
///
/// **Deliberately unstyled.** It renders a `Label` and nothing else: no
/// background, no glass, no accent colour, no padding. Glass adoption across the
/// consuming apps is uneven — some lean on it heavily, several use none at all —
/// so a component that imposed `.glassEffect` would look pasted-in wherever it
/// landed in the second group. The host applies its own chrome:
///
/// ```swift
/// FeedbackLink(app: .silhouette)
///     .buttonStyle(.plain)
///     .padding(.horizontal, 12)
///     .background(.thinMaterial, in: .capsule)
/// ```
///
/// For the same reason there is no shared `HelpView` in this package. Several
/// apps have bespoke, well-designed help sheets running to hundreds of lines;
/// replacing those is a different project, and one that would block this one.
public struct FeedbackLink: View {
  private let app: SupportApp
  private let kind: FeedbackKind
  private let title: String
  private let systemImage: String

  public init(
    app: SupportApp,
    kind: FeedbackKind = .bug,
    title: String = "Send Feedback",
    systemImage: String = "bubble.left.and.exclamationmark.bubble.right"
  ) {
    self.app = app
    self.kind = kind
    self.title = title
    self.systemImage = systemImage
  }

  public var body: some View {
    Link(destination: app.feedbackURL(kind: kind)) {
      Label(title, systemImage: systemImage)
    }
  }
}

/// A link to the public issue tracker. Renders nothing when the app has none,
/// so a call site needs no `if let` of its own.
public struct IssueTrackerLink: View {
  private let app: SupportApp
  private let kind: FeedbackKind
  private let title: String
  private let systemImage: String

  public init(
    app: SupportApp,
    kind: FeedbackKind = .bug,
    title: String = "Report an Issue",
    systemImage: String = "exclamationmark.triangle"
  ) {
    self.app = app
    self.kind = kind
    self.title = title
    self.systemImage = systemImage
  }

  public var body: some View {
    if let url = app.issueURL(kind: kind) {
      Link(destination: url) {
        Label(title, systemImage: systemImage)
      }
    }
  }
}
