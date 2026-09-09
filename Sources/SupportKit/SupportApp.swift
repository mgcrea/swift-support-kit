import Foundation

/// What a user is trying to do when they reach for the feedback affordance.
///
/// Three, not more. The list is a routing hint for triage and a heading for the
/// form; a longer taxonomy makes the person choosing it think harder than the
/// value it returns. Unknown values decode to `.bug` on the receiving side
/// rather than erroring — a misfiled report is still a report.
public enum FeedbackKind: String, Sendable, CaseIterable {
  case bug
  case idea
  case question
}

/// One app's support identity.
///
/// Every consuming app declares exactly one of these, usually as a `static let`
/// in a single file. Nothing else in the package knows an app's name, and that
/// is what makes the four hand-copied `SupportLinks.swift` files collapse into
/// one configuration line each.
public struct SupportApp: Sendable {
  /// Lowercase, hyphenated: `"d1-explorer"`. It is the tracker label, the
  /// `app` query parameter, and the database key — one string in three roles,
  /// so it must not drift between them.
  public let slug: String
  /// `"D1Explorer"` — how the app names itself to a human.
  public let displayName: String
  /// `https://d1-explorer.mgcrea.io`, no trailing slash.
  public let siteURL: URL
  /// Where mail goes when a browser is not the right answer.
  public let supportEmail: String
  /// The public issue tracker, or nil for an app that does not want one
  /// surfaced. Nil hides the link rather than rendering a dead one.
  public let trackerURL: URL?
  /// Defaults to `/feedback/`. Overridable because balise is bilingual and a
  /// French user must land on `/en/feedback/`'s counterpart, not on English.
  public let feedbackPath: String
  /// Defaults to `/support/`, for the same reason.
  public let supportPath: String

  public init(
    slug: String,
    displayName: String,
    siteURL: URL,
    supportEmail: String = "support@mgcrea.io",
    trackerURL: URL? = nil,
    feedbackPath: String = "/feedback/",
    supportPath: String = "/support/"
  ) {
    self.slug = slug
    self.displayName = displayName
    self.siteURL = siteURL
    self.supportEmail = supportEmail
    self.trackerURL = trackerURL
    self.feedbackPath = feedbackPath
    self.supportPath = supportPath
  }
}

extension SupportApp {
  /// The version of the URL contract this package speaks.
  ///
  /// Sent as `v`, and the receiving page rejects a value it does not know with
  /// a message naming the app. That is the drift alarm: nine separately
  /// released apps cannot be updated in lockstep, so the one thing that must
  /// never be ambiguous is which shape of URL arrived.
  public static let contractVersion = 1

  /// A subject seed longer than this is truncated rather than dropped.
  ///
  /// The whole URL has room to spare; this cap exists so a caller passing a
  /// long error message cannot push the diagnostics out of a URL bar the user
  /// is meant to be able to read.
  public static let maxSubjectLength = 120
}
