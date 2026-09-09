import Foundation

// Building the four URLs an app can hand to the system.
//
// Nothing here opens a connection, and that is the point rather than an
// accident. Several consuming apps ship without `com.apple.security.network.client`
// and publish that fact as a checkable claim; one fails its build on any
// URLSession symbol. Handing a URL to the browser or the mail client keeps every
// one of those claims true, and keeps every App Store privacy label at
// "Data Not Collected" — the app transmits nothing, the website does.
//
// A second property falls out of it, and is worth stating because it is rare:
// the URL is *inspectable*. Everything this package discloses is sitting in the
// address bar before the user presses anything. A POST from inside an app can
// only be described; this can be read.

extension SupportApp {
  /// The web feedback form, prefilled.
  ///
  /// The diagnostics ride as query parameters so the page can render them as
  /// visible, editable, deletable fields. They must never become hidden inputs:
  /// "you can see everything it sends" is the claim that makes this design
  /// better than an in-app form rather than merely equivalent to it.
  public func feedbackURL(
    kind: FeedbackKind,
    subject: String? = nil,
    diagnostics: Diagnostics = .current
  ) -> URL {
    var components = URLComponents()
    components.scheme = siteURL.scheme
    components.host = siteURL.host
    components.port = siteURL.port
    components.path = feedbackPath

    var items = [
      URLQueryItem(name: "v", value: String(Self.contractVersion)),
      URLQueryItem(name: "app", value: slug),
      URLQueryItem(name: "kind", value: kind.rawValue),
      URLQueryItem(name: "av", value: diagnostics.appVersion),
      URLQueryItem(name: "os", value: diagnostics.osVersion),
      URLQueryItem(name: "hw", value: diagnostics.hardware),
      URLQueryItem(name: "lang", value: diagnostics.language),
    ]
    if let seed = Self.trimmedSubject(subject) {
      items.append(URLQueryItem(name: "s", value: seed))
    }
    components.queryItems = items

    // The force-unwrap is safe and the alternative is worse: `components`
    // has a scheme, a host and a path taken from an already-valid `URL`, so
    // the only way this returns nil is a `siteURL` that was never a web URL.
    // Returning an optional here would push a `?? someFallbackURL` into
    // every call site, and a fallback support URL is a bug that hides itself.
    return components.url!
  }

  /// The app's support page.
  public var supportURL: URL {
    siteURL.appendingPathComponent(supportPath)
  }

  /// The App Store page, opened straight onto the write-a-review sheet, or nil
  /// for an app that is not on the store.
  ///
  /// `https://apps.apple.com/app/id…?action=write-review`, and **not**
  /// `itms-apps://`. The `itms-apps` scheme is undocumented, and on a machine
  /// where nothing claims it the link does not fail visibly — it does nothing
  /// at all. The `https` form is handled by the App Store app when it is
  /// installed and degrades to the web page when it is not, so there is no path
  /// with nowhere to go.
  ///
  /// Worth a row of its own for the reason `ReviewPrompt` was written: across
  /// the whole portfolio there have been two written reviews, ever — too few for
  /// the store to show a rating overview on any page. `requestReview` is
  /// throttled to roughly three prompts a year and may show nothing; a link in
  /// settings is neither throttled nor tied to a milestone, and costs one row.
  public var appStoreReviewURL: URL? {
    guard let appStoreID, !appStoreID.isEmpty else { return nil }
    return URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")
  }

  /// A prefilled GitHub issue on the shared tracker, or nil when the app does
  /// not surface one.
  ///
  /// Kept as the *secondary* path everywhere. It costs a GitHub account and it
  /// is public — fine for the developer-facing apps, a wall for the ones sold
  /// to photographers and retouchers, who will not post a client's unreleased
  /// artwork to a public tracker to report a bug in it.
  public func issueURL(kind: FeedbackKind, diagnostics: Diagnostics = .current) -> URL? {
    guard let trackerURL else { return nil }
    // The tracker URL points at the app's folder; issues live at the repo root.
    guard
      var components = URLComponents(
        url: trackerURL, resolvingAgainstBaseURL: false)
    else { return nil }
    components.path = Self.issuesPath(from: components.path)
    components.queryItems = [
      URLQueryItem(name: "labels", value: slug),
      URLQueryItem(name: "title", value: "[\(slug)] "),
      URLQueryItem(name: "body", value: issueBody(kind: kind, diagnostics: diagnostics)),
    ]
    return components.url
  }

  /// A prefilled mail draft — the fallback when there is no browser answer.
  ///
  /// **`mailto:` is not an HTTP query and does not share its rules.** Two
  /// differences bite, and both produce a wrong-looking draft rather than an
  /// error:
  ///
  /// - `+` is a literal plus sign, not a space. The existing
  ///   `GITHUB_NEW_ISSUE_URL` constants in the website configs end in `+`
  ///   precisely because that *is* correct for HTTP — reuse one here and the
  ///   subject line reads `[silhouette]+`.
  /// - Line breaks must be CRLF (`%0D%0A`). A bare `%0A` is tolerated by some
  ///   clients and collapsed by others.
  ///
  /// `URLComponents` percent-encodes a space as `%20`, which is right for both,
  /// so the body is built through it rather than by string concatenation.
  public func mailtoURL(kind: FeedbackKind, diagnostics: Diagnostics = .current) -> URL? {
    // `URLComponents` is used for the query **only**, and the `mailto:` head
    // is assembled by hand. Setting `.scheme` and `.path` and reading `.url`
    // back does work — on a new enough OS. macOS 15 still resolves this
    // through the older CFURL implementation, where the same components give
    // an empty `path`, and CI on the package's own deployment floor is what
    // caught it. A support link that silently degrades on the oldest OS a
    // consuming app supports is precisely the bug this package must not have,
    // so the output is made independent of which implementation is present.
    var query = URLComponents()
    query.queryItems = [
      URLQueryItem(name: "subject", value: "[\(slug)] \(kind.rawValue)"),
      URLQueryItem(name: "body", value: mailBody(diagnostics: diagnostics)),
    ]
    guard let encodedQuery = query.percentEncodedQuery else { return nil }
    // The address is percent-encoded too: `urlPathAllowed` keeps `@` and `.`
    // intact, which is what a mailbox needs, while a stray space or unicode
    // in a misconfigured address cannot produce an unparseable URL.
    guard
      let address = supportEmail.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
    else { return nil }
    return URL(string: "mailto:\(address)?\(encodedQuery)")
  }
}

// MARK: - Bodies

extension SupportApp {
  /// The markdown issue template, with the environment already filled in.
  ///
  /// The Mac model line used to ask the user to type it — and the four copies
  /// of this template had already drifted on what to suggest (`M1 / M2 / M3 / M4`
  /// in one, `M1 / M2 / M3 / Intel` in another). A field nobody fills reliably
  /// becomes a field nobody has to.
  func issueBody(kind: FeedbackKind, diagnostics: Diagnostics) -> String {
    let heading =
      switch kind {
      case .bug: "### What happened"
      case .idea: "### What you would like"
      case .question: "### Your question"
      }
    return """
      \(heading)


      ### Steps to reproduce
      1.
      2.
      3.

      ### Expected behaviour


      ### Environment
      - \(displayName): \(diagnostics.appVersion)
      - OS: \(diagnostics.osVersion)
      - Model: \(diagnostics.hardware)

      ### Anything else
      <!-- Screenshots, logs, or anything else that may help -->
      """
  }

  /// The mail body. Shorter than the issue template on purpose: a mail client
  /// is where someone writes prose, and an HTML-comment scaffold read as plain
  /// text is noise they have to delete first.
  ///
  /// The sign-off is `Diagnostics.bugReportSummary` rather than its own
  /// interpolation, and that is load-bearing. The About pane's copy button puts
  /// the same facts on the pasteboard, and two strings describing one machine
  /// that are free to disagree eventually will — the same failure the `v=1`
  /// contract version exists to catch between the app and the website. One of
  /// them would then be wrong in a bug report, and nothing would say which.
  func mailBody(diagnostics: Diagnostics) -> String {
    """


    —
    \(diagnostics.bugReportSummary(for: self))
    """
  }
}

// MARK: - Helpers

extension SupportApp {
  /// `/mgcrea/support/tree/main/silhouette` → `/mgcrea/support/issues/new`.
  ///
  /// The configured tracker URL points at the app's folder because that is the
  /// useful thing to *browse*; issues are filed at the repository root. Slicing
  /// at `/tree/` keeps one configured URL serving both, so an app cannot be
  /// given a browse link and a file link that disagree.
  static func issuesPath(from path: String) -> String {
    let root =
      path.range(of: "/tree/").map { String(path[path.startIndex..<$0.lowerBound]) } ?? path
    return root.hasSuffix("/") ? root + "issues/new" : root + "/issues/new"
  }

  /// Trim, drop if empty, and truncate to the cap on a character boundary.
  ///
  /// Truncation is by `Character`, not by UTF-8 byte or UTF-16 unit, so a
  /// subject ending in an emoji or a combining accent cannot be cut in half.
  static func trimmedSubject(_ subject: String?) -> String? {
    guard let subject else { return nil }
    let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    guard trimmed.count > maxSubjectLength else { return trimmed }
    return String(trimmed.prefix(maxSubjectLength))
  }
}
