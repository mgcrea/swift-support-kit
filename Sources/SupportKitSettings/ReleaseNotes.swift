import SwiftUI

/// One released version, as an app's What's New pane draws it.
///
/// The fleet generates these from each app's `CHANGELOG.md` at build time rather
/// than bundling the markdown and parsing it at launch: the parse then runs once,
/// in Node, where a `--check` gate can assert the result. That generator stays in
/// each app. This package owns only the shape it writes and everything that reads
/// it, which is the half four apps had copied by hand and let drift.
///
/// Every string is **raw markdown**. The generator does not decide what bold
/// looks like; `ReleaseNotes.markdown(_:_:)` renders it.
///
/// An app's generated file usually declares its literals inside its own
/// `Changelog` enum, with `typealias Release = ChangelogRelease` (and `Section`,
/// `Entry`) so the emitted code reads `Release(…)` rather than the long names.
public struct ChangelogRelease: Identifiable, Hashable, Sendable {
  /// `"1.0.0"`. Compared against the installed version and the seen key.
  public let version: String
  /// `"2026-09-14"`, or empty for a version that is written down and not yet
  /// dated — `## [1.4.0] - Unreleased`, which is what a TestFlight build carries.
  /// Kept as the ISO string the CHANGELOG wrote rather than a `Date`: a
  /// `Date(timeIntervalSince1970:)` in a generated file is unreadable in a diff,
  /// and formatting at generation time would bake the generating machine's locale
  /// into every build.
  public let date: String
  public let sections: [Section]

  public var id: String { version }

  public init(version: String, date: String, sections: [Section]) {
    self.version = version
    self.date = date
    self.sections = sections
  }

  /// One `### Added` / `### Fixed` block.
  ///
  /// `name` is whatever the CHANGELOG wrote, so nothing here is an enum. The pane
  /// translates the Keep a Changelog names it knows and draws any other verbatim.
  public struct Section: Identifiable, Hashable, Sendable {
    public let name: String
    /// The prose that can sit between the heading and the first bullet.
    /// Dropping it silently shortens the notes, which is exactly the kind of loss
    /// nothing would report.
    public let lead: [String]
    public let entries: [Entry]

    public var id: String { name }

    public init(name: String, lead: [String], entries: [Entry]) {
      self.name = name
      self.lead = lead
      self.entries = entries
    }
  }

  /// One bullet.
  public struct Entry: Identifiable, Hashable, Sendable {
    /// Emitted rather than derived, so `ForEach` has a stable identity without
    /// hashing prose or inventing a `UUID` that changes every render.
    ///
    /// **Unique across the whole release**, not within its section. SwiftUI
    /// flattens the section/entry `ForEach` pair inside a `Form`, so per-section
    /// numbering collides as soon as a release has two sections — and the pane
    /// then draws the first section's bullet a second time in place of the
    /// second section's. A generator must number across the release.
    public let ordinal: Int
    /// The leading `**…**`, asterisks removed — or nil. Not every bullet opens
    /// with one, so this is an optional by observation rather than by caution.
    public let headline: String?
    /// The rest, one string per paragraph.
    public let body: [String]

    public var id: Int { ordinal }

    public init(ordinal: Int, headline: String?, body: [String]) {
      self.ordinal = ordinal
      self.headline = headline
      self.body = body
    }
  }
}

/// An app's release notes, and the record of which of them have been read.
///
/// A value an app builds once, from its generated data, and hands to both the
/// sidebar badge and `WhatsNewSettingsPane`:
///
/// ```swift
/// nonisolated enum Changelog {
///   static let notes = ReleaseNotes(
///     releases: releases, unreleased: unreleased, showsUnreleased: AppInfo.isDebugBuild)
///   // <generated:changelog> … </generated:changelog>
/// }
///
/// var badge: Int { self == .whatsNew ? Changelog.notes.badge : 0 }
/// ```
///
/// `Sendable` and actor-free, because `SettingsPane.badge` reads it and that
/// requirement has no actor to run on. Nothing here needs one: the members are
/// constants, `UserDefaults` and the bundle.
public struct ReleaseNotes: Sendable {
  /// The releases the app chose to ship, newest first.
  public let releases: [ChangelogRelease]
  /// `## [Unreleased]`, or nil. Carried by every build, drawn only when
  /// `showsUnreleased`.
  public let unreleased: ChangelogRelease?
  /// The marketing version alone: no build number, no `-dev`. What the
  /// "installed" badge and the seen key compare against.
  public let installedVersion: String
  /// Whether this build may draw `unreleased`. A parameter rather than a
  /// `#if DEBUG` in here, because the flag that matters is the app's build
  /// configuration, not this package's.
  public let showsUnreleased: Bool
  /// The defaults key holding the last version whose notes were read.
  public let seenKey: String

  /// A suite name rather than a `UserDefaults`, which is not `Sendable`. Nil is
  /// `.standard`.
  private let defaultsSuite: String?
  private let isSuppressed: @Sendable () -> Bool

  /// - Parameters:
  ///   - installedVersion: defaults to `CFBundleShortVersionString`. Never pass a
  ///     display version such as `"1.0.0 (60)"` or `"1.0.0-dev"`: it would never
  ///     equal a release, so nothing would be marked "installed" and every read
  ///     would store a version no release is newer than.
  ///   - seenKey: the key the four apps already write. Changing it re-badges
  ///     every release the user had read.
  ///   - isSuppressed: true while a screenshot capture runs. A suppressed notes
  ///     value reports nothing unread and records nothing as read, so a golden
  ///     does not depend on what the capturing Mac last opened, and a capture run
  ///     does not clear the developer's own badge. Evaluated on every read.
  public init(
    releases: [ChangelogRelease],
    unreleased: ChangelogRelease? = nil,
    installedVersion: String = ReleaseNotes.bundleVersion,
    showsUnreleased: Bool,
    seenKey: String = "changelogSeenVersion",
    defaultsSuite: String? = nil,
    isSuppressed: @escaping @Sendable () -> Bool = { false }
  ) {
    self.releases = releases
    self.unreleased = unreleased
    self.installedVersion = installedVersion
    self.showsUnreleased = showsUnreleased
    self.seenKey = seenKey
    self.defaultsSuite = defaultsSuite
    self.isSuppressed = isSuppressed
  }

  /// `CFBundleShortVersionString` of the main bundle, or empty.
  public static var bundleVersion: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
  }

  private var defaults: UserDefaults {
    defaultsSuite.flatMap(UserDefaults.init(suiteName:)) ?? .standard
  }

  // MARK: - Seen

  /// Seed the seen version on a launch that has never set it.
  ///
  /// Call once at launch, before anything reads `badge`. Without it a fresh
  /// install lights the indicator on first launch — the key is absent, so
  /// everything looks unread, and the app greets somebody who has never run it
  /// with a stack of "new" releases. The cost is that the indicator does nothing
  /// until the *next* release; the alternative costs every new user a false badge.
  public func markSeenIfUnset() {
    guard !isSuppressed(), defaults.string(forKey: seenKey) == nil else { return }
    markSeen()
  }

  /// Record that the notes for this build have been read.
  public func markSeen() {
    guard !isSuppressed() else { return }
    defaults.set(installedVersion, forKey: seenKey)
  }

  /// Releases newer than the last one whose notes were read.
  ///
  /// Empty rather than everything when the key is unset — see `markSeenIfUnset()`.
  /// Not suppressed: the pane reads this to decide which headers say "new", and
  /// `badge` is where suppression applies.
  public var unseen: [ChangelogRelease] {
    guard let seen = defaults.string(forKey: seenKey), !seen.isEmpty else { return [] }
    return releases.filter { Self.isVersion($0.version, newerThan: seen) }
  }

  /// The count for `SettingsPane.badge`: unread releases, or zero while suppressed.
  public var badge: Int {
    isSuppressed() ? 0 : unseen.count
  }

  /// `a` is a later release than `b`, comparing dotted numbers.
  ///
  /// Numeric per component, so `1.10.0` is correctly newer than `1.9.0` — the
  /// comparison a lexicographic one gets backwards. Anything non-numeric compares
  /// as 0, which makes an unparseable version "not newer" rather than a crash.
  public static func isVersion(_ a: String, newerThan b: String) -> Bool {
    let left = a.split(separator: ".").map { Int($0) ?? 0 }
    let right = b.split(separator: ".").map { Int($0) ?? 0 }
    for index in 0..<max(left.count, right.count) {
      let l = index < left.count ? left[index] : 0
      let r = index < right.count ? right[index] : 0
      if l != r { return l > r }
    }
    return false
  }

  // MARK: - Rendering

  /// One markdown string as `Text` can draw it.
  ///
  /// `Text` honours `**bold**`, `_italic_` and links from an `AttributedString`
  /// on its own. It does nothing at all for `` `code` `` — the markdown parser
  /// records that as a semantic `inlinePresentationIntent` and applies no font —
  /// so the loop below is the whole of the missing half.
  ///
  /// The style is a parameter because setting `.font` on a run **overrides** the
  /// view's own `.font()` for that run: a body-sized helper used inside a caption
  /// makes one word jump a size. And the emphasis has to be reapplied, because
  /// headlines contain code spans inside the bold — assigning a plain monospaced
  /// font would silently un-bold them.
  ///
  /// `Text("**bold**")` renders markdown only for string *literals*, through the
  /// `LocalizedStringKey` overload. Every string here is a variable, which takes
  /// the `StringProtocol` overload and draws the asterisks, so this is not an
  /// embellishment; without it the pane shows raw markdown.
  public static func markdown(_ source: String, _ style: Font.TextStyle = .body)
    -> AttributedString
  {
    guard
      var text = try? AttributedString(
        markdown: source,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
    else {
      // Literal asterisks are ugly and honest. Nothing here is worth a crash.
      return AttributedString(source)
    }
    for run in text.runs {
      guard let intent = run.inlinePresentationIntent, intent.contains(.code) else { continue }
      var font = Font.system(style, design: .monospaced)
      if intent.contains(.stronglyEmphasized) { font = font.bold() }
      if intent.contains(.emphasized) { font = font.italic() }
      text[run.range].font = font
    }
    return text
  }
}
