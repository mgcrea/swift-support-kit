import Foundation
import Testing

@testable import SupportKit

/// A fixed machine, so every assertion below is exact rather than "whatever this
/// laptop happens to be". `Diagnostics.current` is tested separately.
private let fixture = Diagnostics(
  appVersion: "1.4 (168)",
  osVersion: "macOS 26.4",
  hardware: "Mac16,10",
  language: "en"
)

private let silhouette = SupportApp(
  slug: "silhouette",
  displayName: "Silhouette",
  siteURL: URL(string: "https://silhouette.mgcrea.io")!,
  trackerURL: URL(string: "https://github.com/mgcrea/support/tree/main/silhouette")!
)

/// Query parameters as a dictionary — order is not part of the contract, and
/// asserting on a whole URL string would make every test brittle to reordering.
private func params(_ url: URL) -> [String: String] {
  let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
  return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, b in b })
}

@Suite("Feedback URL")
struct FeedbackURLTests {
  @Test("carries the contract version, slug, kind and every diagnostic")
  func carriesEverything() {
    let url = silhouette.feedbackURL(kind: .idea, diagnostics: fixture)
    let q = params(url)
    #expect(url.host == "silhouette.mgcrea.io")
    // `URL.path` normalises the trailing slash away, so assert on what is
    // actually emitted — see `keepsTheTrailingSlash` for why it matters.
    #expect(url.absoluteString.hasPrefix("https://silhouette.mgcrea.io/feedback/?"))
    #expect(q["v"] == "1")
    #expect(q["app"] == "silhouette")
    #expect(q["kind"] == "idea")
    #expect(q["av"] == "1.4 (168)")
    #expect(q["os"] == "macOS 26.4")
    #expect(q["hw"] == "Mac16,10")
    #expect(q["lang"] == "en")
  }

  @Test("every kind round-trips through the query", arguments: FeedbackKind.allCases)
  func everyKind(kind: FeedbackKind) {
    #expect(
      params(silhouette.feedbackURL(kind: kind, diagnostics: fixture))["kind"] == kind.rawValue)
  }

  @Test("omits the subject entirely when there is none")
  func noSubject() {
    #expect(params(silhouette.feedbackURL(kind: .bug, diagnostics: fixture))["s"] == nil)
  }

  @Test("omits a subject that is only whitespace")
  func blankSubject() {
    let url = silhouette.feedbackURL(kind: .bug, subject: "   \n ", diagnostics: fixture)
    #expect(params(url)["s"] == nil)
  }

  /// The encoding assertion that matters: a space must not become `+`, and the
  /// characters that would end the query must not survive raw.
  @Test("percent-encodes a subject that needs it, and never as +")
  func encodesSubject() {
    let raw = "Export failed: 100% of it & then some / naïve"
    let url = silhouette.feedbackURL(kind: .bug, subject: raw, diagnostics: fixture)
    #expect(params(url)["s"] == raw)

    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.percentEncodedQuery!
    #expect(!query.contains("+"))
    #expect(query.contains("%20"))
  }

  @Test("truncates an over-long subject and drops nothing else")
  func truncatesSubject() {
    let long = String(repeating: "a", count: SupportApp.maxSubjectLength + 50)
    let q = params(silhouette.feedbackURL(kind: .bug, subject: long, diagnostics: fixture))
    #expect(q["s"]?.count == SupportApp.maxSubjectLength)
    // Everything else still present — truncation must not cost a diagnostic.
    #expect(q["av"] == "1.4 (168)")
    #expect(q["hw"] == "Mac16,10")
    #expect(q["lang"] == "en")
  }

  /// Truncating by `Character` rather than by UTF-8 byte: an emoji at the
  /// boundary must survive whole or not at all.
  @Test("never splits a grapheme when truncating")
  func truncatesOnGraphemeBoundary() {
    let long = String(repeating: "👨‍👩‍👧‍👦", count: SupportApp.maxSubjectLength + 10)
    let seed = params(silhouette.feedbackURL(kind: .bug, subject: long, diagnostics: fixture))["s"]
    #expect(seed?.count == SupportApp.maxSubjectLength)
    #expect(seed?.hasSuffix("👨‍👩‍👧‍👦") == true)
  }

  @Test("honours a custom feedback path, for the bilingual site")
  func customPath() {
    let english = SupportApp(
      slug: "balise",
      displayName: "Balise",
      siteURL: URL(string: "https://balise.mgcrea.io")!,
      feedbackPath: "/en/feedback/"
    )
    let url = english.feedbackURL(kind: .bug, diagnostics: fixture)
    #expect(url.absoluteString.hasPrefix("https://balise.mgcrea.io/en/feedback/?"))
  }

  /// The trailing slash is load-bearing, not cosmetic.
  ///
  /// Balise's site routes `/feedback` and `/feedback/` differently — its
  /// wrangler `run_worker_first` list keys on the exact form — so a builder
  /// that quietly dropped it would send French users to a 404 while every
  /// other app kept working.
  @Test("keeps the trailing slash the site routes on")
  func keepsTheTrailingSlash() {
    let url = silhouette.feedbackURL(kind: .bug, diagnostics: fixture)
    #expect(url.absoluteString.contains("/feedback/?"))
    #expect(!url.absoluteString.contains("/feedback?"))
  }
}

@Suite("Issue URL")
struct IssueURLTests {
  @Test("files at the repository root, not inside the app's folder")
  func rewritesTreePath() {
    let url = silhouette.issueURL(kind: .bug, diagnostics: fixture)!
    #expect(url.path == "/mgcrea/support/issues/new")
  }

  @Test("labels and titles with the slug")
  func labelsAndTitle() {
    let q = params(silhouette.issueURL(kind: .bug, diagnostics: fixture)!)
    #expect(q["labels"] == "silhouette")
    #expect(q["title"] == "[silhouette] ")
  }

  @Test("prefills the environment so nobody has to type their Mac model")
  func bodyCarriesEnvironment() {
    let body = params(silhouette.issueURL(kind: .bug, diagnostics: fixture)!)["body"] ?? ""
    #expect(body.contains("Silhouette: 1.4 (168)"))
    #expect(body.contains("OS: macOS 26.4"))
    #expect(body.contains("Model: Mac16,10"))
  }

  @Test("heads the body differently per kind", arguments: FeedbackKind.allCases)
  func headingPerKind(kind: FeedbackKind) {
    let body = params(silhouette.issueURL(kind: kind, diagnostics: fixture)!)["body"] ?? ""
    #expect(body.hasPrefix("### "))
  }

  @Test("is nil for an app with no tracker, rather than a dead link")
  func nilWithoutTracker() {
    let app = SupportApp(
      slug: "x", displayName: "X", siteURL: URL(string: "https://x.mgcrea.io")!)
    #expect(app.issueURL(kind: .bug, diagnostics: fixture) == nil)
  }
}

@Suite("mailto URL")
struct MailtoURLTests {
  /// Asserted on `absoluteString`, not on `url.path`.
  ///
  /// `URLComponents` gives `mailto:` a path on macOS 26 and an empty one on
  /// macOS 15, so `path` is not a stable thing to assert. What actually gets
  /// handed to LaunchServices is the whole string.
  @Test("addresses the support mailbox")
  func addressesSupport() {
    let url = silhouette.mailtoURL(kind: .bug, diagnostics: fixture)!
    #expect(url.scheme == "mailto")
    #expect(url.absoluteString.hasPrefix("mailto:support@mgcrea.io?"))
  }

  /// The trap this whole method exists to avoid. In a `mailto:` URL `+` is a
  /// literal plus, so a subject encoded the HTTP way arrives visibly wrong.
  @Test("encodes spaces as %20 and never as +")
  func neverPlus() {
    let url = silhouette.mailtoURL(kind: .question, diagnostics: fixture)!
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.percentEncodedQuery!
    #expect(!query.contains("+"))
    #expect(params(url)["subject"] == "[silhouette] question")
  }

  /// The sign-off is `Diagnostics.bugReportSummary`, so this asserts the same
  /// two lines the About pane's copy button puts on the pasteboard. That is the
  /// point of the shared function: a mail trailer and a pasted block that
  /// describe one machine and are free to disagree eventually will, and nothing
  /// would say which of them was wrong.
  @Test("signs off with the environment")
  func bodyCarriesEnvironment() {
    let body = params(silhouette.mailtoURL(kind: .bug, diagnostics: fixture)!)["body"] ?? ""
    #expect(body.contains("Silhouette 1.4 (168)"))
    #expect(body.contains("macOS 26.4 · Mac16,10 · en"))
    #expect(body.contains(fixture.bugReportSummary(for: silhouette)))
  }
}

@Suite("Support URL")
struct SupportURLTests {
  @Test("hangs off the app's own site")
  func onOwnSite() {
    #expect(silhouette.supportURL.absoluteString.hasPrefix("https://silhouette.mgcrea.io"))
    #expect(silhouette.supportURL.path.contains("/support"))
  }
}
