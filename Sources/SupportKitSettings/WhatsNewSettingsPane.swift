import SwiftUI

/// What changed, in the build that is running. What a pane enum's `.whatsNew`
/// case returns.
///
/// Release notes otherwise reach people in exactly one place — the App Store's
/// Updates page, or the sheet Sparkle shows while it asks to install — and most
/// people update without reading either. This is where somebody who has just
/// noticed something new can look it up, and `ReleaseNotes.badge` on the sidebar
/// row says there is something to look up. A pane rather than a window that
/// appears after an update: the fleet's menu bar agents promise to stay out of
/// the way, and a window seizing focus on the first launch of a new build would
/// break that for news that can wait.
///
/// Written four times — Cupertino, Armada, Bastion, Cadence — before it moved
/// here, and the copies had started to differ in their fixes rather than their
/// app names.
public struct WhatsNewSettingsPane: View {
  private let notes: ReleaseNotes
  private let historyURL: URL?
  private let footer: LocalizedStringKey?

  /// Which releases were unread when this pane was opened.
  ///
  /// Captured once in `onAppear`, before `markSeen()` runs, and then held.
  /// Reading `notes.unseen` live would clear every "new" badge in the same frame
  /// that draws them — the user would arrive to find the thing they came to read
  /// already marked as read.
  @State private var wasUnseen: Set<String> = []
  @State private var expanded: Set<String> = []

  /// - Parameters:
  ///   - historyURL: the full `CHANGELOG.md`, drawn as a link under the notes.
  ///     Nil omits it — the right answer for an app whose repository is private,
  ///     where the link would lead to a 404.
  ///   - footer: a sentence under the notes, in the **app's** catalog, since it
  ///     usually names the app. Nil draws none.
  public init(notes: ReleaseNotes, historyURL: URL? = nil, footer: LocalizedStringKey? = nil) {
    self.notes = notes
    self.historyURL = historyURL
    self.footer = footer
  }

  private var recent: [ChangelogRelease] {
    notes.releases.filter {
      $0.version == notes.releases.first?.version || wasUnseen.contains($0.version)
    }
  }

  private var earlier: [ChangelogRelease] {
    notes.releases.filter { release in !recent.contains { $0.version == release.version } }
  }

  public var body: some View {
    Form {
      // Debug only, and the section says so rather than relying on the reader
      // noticing an unusual version string. A Release build carries the text and
      // never draws it: it describes work that is not in that build.
      if notes.showsUnreleased, let unreleased = notes.unreleased {
        Section {
          ReleaseBody(release: unreleased)
        } header: {
          HStack(spacing: 6) {
            Text(localized("Unreleased"))
            ReleaseBadge(localized("not in any build"), tint: .orange)
          }
        }
      }

      ForEach(recent) { release in
        Section {
          ReleaseBody(release: release)
        } header: {
          ReleaseHeader(
            release: release,
            isNew: wasUnseen.contains(release.version),
            isInstalled: release.version == notes.installedVersion)
        }
      }

      if !earlier.isEmpty {
        Section {
          ForEach(earlier) { release in
            DisclosureGroup(isExpanded: binding(for: release.version)) {
              ReleaseBody(release: release)
            } label: {
              ReleaseHeader(
                release: release, isNew: false,
                isInstalled: release.version == notes.installedVersion)
            }
          }
        } header: {
          Text(localized("Earlier releases"))
        }
      }

      if historyURL != nil || footer != nil {
        Section {
          if let historyURL {
            Link(localized("Full changelog"), destination: historyURL)
          }
          if let footer {
            Text(footer)
              .font(.caption).foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    }
    .formStyle(.grouped)
    // Somebody reading a fix wants to paste its symbol name into a search.
    .textSelection(.enabled)
    .onAppear {
      // Order matters: capture what was unread, then mark it read.
      wasUnseen = Set(notes.unseen.map(\.version))
      notes.markSeen()
    }
  }

  private func binding(for version: String) -> Binding<Bool> {
    Binding(
      get: { expanded.contains(version) },
      set: { isExpanded in
        if isExpanded {
          expanded.insert(version)
        } else {
          expanded.remove(version)
        }
      })
  }
}

// MARK: - One release

private struct ReleaseHeader: View {
  let release: ChangelogRelease
  let isNew: Bool
  let isInstalled: Bool

  var body: some View {
    HStack(spacing: 6) {
      Text(verbatim: release.version)
      if isNew { ReleaseBadge(localized("new"), tint: .accentColor) }
      if isInstalled { ReleaseBadge(localized("installed"), tint: .secondary) }
      Spacer()
      // A version written down before it has a date is the one in TestFlight.
      if !release.date.isEmpty {
        Text(formattedDate)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  /// Absolute, never relative. `.relative` would read better — "3 days ago" —
  /// and would be computed against `Date()`, so the pane would say something
  /// different every day about a fact that never changes.
  private var formattedDate: String {
    guard
      let date = try? Date(
        release.date, strategy: .iso8601.year().month().day().dateSeparator(.dash))
    else { return release.date }
    return date.formatted(date: .abbreviated, time: .omitted)
  }
}

private struct ReleaseBody: View {
  let release: ChangelogRelease

  /// One row of a release, flattened, with an id that cannot collide.
  ///
  /// The sections are NOT a nested `ForEach`, and that is a bug fix rather than
  /// a tidy-up. SwiftUI flattens nested `ForEach`es inside a `Form`, so every id
  /// in them shares one space — and a lead paragraph keyed by its offset (0)
  /// collided with the release's first entry keyed by its ordinal (0), drawing
  /// one of the two twice and the other never. Building the rows here, with
  /// string ids carrying the section name, means there is only one id space and
  /// it is one this file controls.
  private struct Row: Identifiable {
    let id: String
    let section: String
    let lead: String?
    let entry: ChangelogRelease.Entry?
  }

  ///
  /// Keyed by the section's position rather than its name: notes with no sections, the App
  /// Store's, come as sections with no name, and two of them would share every id.
  private var rows: [Row] {
    release.sections.enumerated().flatMap { index, section in
      section.lead.enumerated().map {
        Row(
          id: "\(index).lead.\($0.offset)", section: section.name, lead: $0.element, entry: nil)
      }
        + section.entries.map {
          Row(id: "\(index).entry.\($0.ordinal)", section: section.name, lead: nil, entry: $0)
        }
    }
  }

  var body: some View {
    ForEach(rows) { row in
      if let lead = row.lead {
        Text(ReleaseNotes.markdown(lead, .caption))
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      } else if let entry = row.entry {
        EntryRow(section: row.section, entry: entry)
      }
    }
  }
}

/// One bullet, with its section as a badge rather than as a heading.
///
/// A grouped `Form` already spends a header on each release; adding `Added` and
/// `Fixed` as a second heading level inside that is three levels of hierarchy in
/// a settings window. The badge says the same thing in the space the bullet
/// already occupies.
///
/// A section with no name draws no badge: notes with no sections, such as an App
/// Store listing's, would otherwise carry an empty capsule on every point.
private struct EntryRow: View {
  let section: String
  let entry: ChangelogRelease.Entry

  private var layout: EntryLayout { EntryLayout(entry) }
  private var label: String { ReleaseSectionLabel.label(for: section) }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        if !label.isEmpty {
          ReleaseBadge(label, tint: Self.tint(for: section))
        }
        if let opening = layout.opening {
          Text(ReleaseNotes.markdown(opening, .callout))
            .font(.callout)
            .bold(layout.isHeadline)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      ForEach(Array(layout.details.enumerated()), id: \.offset) { _, paragraph in
        Text(ReleaseNotes.markdown(paragraph, .caption))
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.vertical, 2)
  }

  /// Colour carries the same information as the word, for the glance that does
  /// not read it. Red for Security specifically: it is the one section whose
  /// presence should change whether somebody defers an update.
  private static func tint(for section: String) -> Color {
    switch section {
    case "Added": .green
    case "Changed": .blue
    case "Fixed": .orange
    case "Security": .red
    default: .secondary
    }
  }
}

/// How one bullet is drawn: the line beside its badge, and the grey paragraphs under it.
struct EntryLayout: Equatable {
  /// The line beside the badge, in the bullet's own type. Nil only for an entry with no
  /// text at all.
  let opening: String?
  /// Whether `opening` is a headline, drawn bold.
  let isHeadline: Bool
  /// The paragraphs after it, in grey.
  let details: [String]

  init(_ entry: ChangelogRelease.Entry) {
    if let headline = entry.headline {
      // Whether the bold lead is a headline or just the start of a sentence.
      //
      // Both are written in the fleet's CHANGELOGs. Most entries open with a
      // complete sentence — "**Sessions, per account.**" — which reads well pulled
      // onto its own line. Others bold only the subject and run straight on, and
      // splitting that one puts a line break before a comma and strands the clause
      // that explains it, so it is not split. Sentence-final punctuation is the test
      // because it is the thing the author actually decided.
      if let last = headline.last, ".!?:".contains(last) {
        opening = headline
        isHeadline = true
        details = entry.body
      } else {
        opening = Self.flowing(headline, into: entry.body.first)
        isHeadline = false
        details = Array(entry.body.dropFirst())
      }
    } else {
      // No bold lead: the bullet's first paragraph is the bullet, not a detail of one.
      // It used to be drawn in grey under an empty line, which is how every point of a
      // store listing's notes would have looked.
      opening = entry.body.first
      isHeadline = false
      details = Array(entry.body.dropFirst())
    }
  }

  /// The first paragraph, reassembled, for a bold lead that runs straight on.
  ///
  /// The generator strips the whitespace between the two, so the space has to be
  /// put back — except before punctuation that never takes one.
  private static func flowing(_ headline: String, into first: String?) -> String {
    guard let first, let next = first.first else { return "**\(headline)**" }
    let joiner = ",.;:!?)".contains(next) ? "" : " "
    return "**\(headline)**\(joiner)\(first)"
  }
}

/// A word and a colour, for a fact too small to be a sentence.
private struct ReleaseBadge: View {
  let text: String
  let tint: Color

  init(_ text: String, tint: Color) {
    self.text = text
    self.tint = tint
  }

  var body: some View {
    Text(text)
      .font(.caption2)
      .padding(.horizontal, 6).padding(.vertical, 1)
      .background(tint.opacity(0.15), in: Capsule())
      .foregroundStyle(tint)
  }
}

/// The badge word for a section.
///
/// The Keep a Changelog names, translated; anything else lowercased and drawn as
/// the CHANGELOG wrote it. A switch of literal lookups rather than
/// `localized(section)`: the catalog guard can only see a key written at the
/// call, and a key built from a variable would be reported missing and orphaned
/// at once.
enum ReleaseSectionLabel {
  static func label(for section: String) -> String {
    switch section {
    case "Added": localized("added")
    case "Changed": localized("changed")
    case "Deprecated": localized("deprecated")
    case "Removed": localized("removed")
    case "Fixed": localized("fixed")
    case "Security": localized("security")
    // No section, as in notes that have none: no badge rather than an empty one.
    case "": ""
    default: section.lowercased()
    }
  }
}
