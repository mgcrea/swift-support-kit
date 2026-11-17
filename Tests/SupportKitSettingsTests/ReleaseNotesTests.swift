import Foundation
import Testing

@testable import SupportKitSettings

private func release(_ version: String) -> ChangelogRelease {
  ChangelogRelease(version: version, date: "2026-09-14", sections: [])
}

/// A private suite per test, so no test sees another's seen key.
private func notes(
  installed: String, suppressed: Bool = false
) -> (ReleaseNotes, UserDefaults) {
  let suite = "ReleaseNotesTests.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suite)!
  defaults.removePersistentDomain(forName: suite)
  let notes = ReleaseNotes(
    releases: [release("1.10.0"), release("1.2.0"), release("1.1.0"), release("1.0.0")],
    installedVersion: installed,
    showsUnreleased: false,
    defaultsSuite: suite,
    isSuppressed: { suppressed })
  return (notes, defaults)
}

@Suite("Release notes")
struct ReleaseNotesTests {
  @Test("Versions compare numerically, component by component")
  func versionComparison() {
    #expect(ReleaseNotes.isVersion("1.10.0", newerThan: "1.9.0"))
    #expect(ReleaseNotes.isVersion("2.0", newerThan: "1.99.99"))
    #expect(ReleaseNotes.isVersion("1.0.1", newerThan: "1.0"))
    #expect(!ReleaseNotes.isVersion("1.0.0", newerThan: "1.0"))
    #expect(!ReleaseNotes.isVersion("1.0.0", newerThan: "1.0.0"))
    #expect(!ReleaseNotes.isVersion("garbage", newerThan: "0.0.1"))
  }

  @Test("A fresh install has nothing unread, and seeding keeps it that way")
  func freshInstall() {
    let (notes, defaults) = notes(installed: "1.10.0")
    #expect(notes.unseen.isEmpty)
    #expect(notes.badge == 0)

    notes.markSeenIfUnset()
    #expect(defaults.string(forKey: notes.seenKey) == "1.10.0")
    #expect(notes.badge == 0)
  }

  @Test("Seeding never overwrites a version already read")
  func seedingKeepsExisting() {
    let (notes, defaults) = notes(installed: "1.10.0")
    defaults.set("1.1.0", forKey: notes.seenKey)
    notes.markSeenIfUnset()
    #expect(defaults.string(forKey: notes.seenKey) == "1.1.0")
  }

  @Test("Releases newer than the last one read are unseen, and reading clears them")
  func unseenAfterUpdate() {
    let (notes, defaults) = notes(installed: "1.10.0")
    defaults.set("1.1.0", forKey: notes.seenKey)
    #expect(notes.unseen.map(\.version) == ["1.10.0", "1.2.0"])
    #expect(notes.badge == 2)

    notes.markSeen()
    #expect(notes.unseen.isEmpty)
    #expect(notes.badge == 0)
  }

  @Test("A suppressed value reports no badge and records nothing")
  func suppressed() {
    let (notes, defaults) = notes(installed: "1.10.0", suppressed: true)
    notes.markSeenIfUnset()
    #expect(defaults.string(forKey: notes.seenKey) == nil)

    defaults.set("1.1.0", forKey: notes.seenKey)
    #expect(notes.badge == 0)
    notes.markSeen()
    #expect(defaults.string(forKey: notes.seenKey) == "1.1.0")
  }

  @Test("Markdown renders emphasis and keeps bold on code spans")
  func markdown() {
    let text = ReleaseNotes.markdown("**Fixed `foo()` crash.** Plain")
    #expect(String(text.characters) == "Fixed foo() crash. Plain")
    let code = text.runs.first { String(text[$0.range].characters) == "foo()" }
    #expect(code?.font != nil)
    #expect(code?.inlinePresentationIntent?.contains(.stronglyEmphasized) == true)
  }

  @Test("Unparseable markdown falls back to the literal text")
  func markdownFallback() {
    #expect(String(ReleaseNotes.markdown("plain").characters) == "plain")
  }

  @Test("Known section names are translated; others pass through lowercased")
  func sectionLabels() {
    #expect(ReleaseSectionLabel.label(for: "Fixed") == "fixed")
    #expect(ReleaseSectionLabel.label(for: "Performance") == "performance")
  }
}

// MARK: - More than one language

private func entry(_ ordinal: Int, _ text: String) -> ChangelogRelease.Entry {
  ChangelogRelease.Entry(ordinal: ordinal, headline: nil, body: [text])
}

private func notes(_ version: String, _ text: String, date: String = "2026-11-05")
  -> ChangelogRelease
{
  ChangelogRelease(
    version: version, date: date,
    sections: [ChangelogRelease.Section(name: "", lead: [], entries: [entry(0, text)])])
}

private let bilingual: [String: [ChangelogRelease]] = [
  "en": [notes("1.2.0", "Share a tree."), notes("1.1.0", "In French.")],
  // 1.1.0 was never translated, and the French list dates 1.2.0 differently.
  "fr": [notes("1.2.0", "Partagez un arbre.", date: "1999-01-01")],
]

private func firstText(_ release: ChangelogRelease) -> String? {
  release.sections.first?.entries.first?.body.first
}

@Suite("Release notes in more than one language")
struct LocalizedReleaseNotesTests {
  @Test("The app's language is drawn where it was written")
  func appLanguage() {
    let releases = ReleaseNotes.resolve(bilingual, sourceLanguage: "en", appLanguages: ["fr"])
    #expect(releases.map(\.version) == ["1.2.0", "1.1.0"])
    #expect(firstText(releases[0]) == "Partagez un arbre.")
  }

  @Test("A regional variant of the app's language takes the notes' plain language")
  func regionalVariant() {
    let releases = ReleaseNotes.resolve(bilingual, sourceLanguage: "en", appLanguages: ["fr-CA"])
    #expect(firstText(releases[0]) == "Partagez un arbre.")
  }

  @Test("A version nobody translated is listed in the source language")
  func perReleaseFallback() {
    let releases = ReleaseNotes.resolve(bilingual, sourceLanguage: "en", appLanguages: ["fr"])
    #expect(firstText(releases[1]) == "In French.")
  }

  @Test("The source language decides the date")
  func sourceDecidesTheDate() {
    let releases = ReleaseNotes.resolve(bilingual, sourceLanguage: "en", appLanguages: ["fr"])
    #expect(releases[0].date == "2026-11-05")
  }

  @Test("An English app shows English notes, and a language with none falls back to them")
  func otherLanguages() {
    for languages in [["en"], ["de"]] {
      let releases = ReleaseNotes.resolve(
        bilingual, sourceLanguage: "en", appLanguages: languages)
      #expect(firstText(releases[0]) == "Share a tree.")
    }
  }

  @Test("The multilingual init hands the badge the resolved releases")
  func initResolves() {
    let notes = ReleaseNotes(
      localizedReleases: bilingual, appLanguages: ["fr"], installedVersion: "1.2.0",
      showsUnreleased: false, defaultsSuite: "LocalizedReleaseNotesTests.\(UUID().uuidString)")
    #expect(notes.releases.map(\.version) == ["1.2.0", "1.1.0"])
    #expect(firstText(notes.releases[0]) == "Partagez un arbre.")
  }
}

// MARK: - Entries

@Suite("What's New entries")
struct EntryLayoutTests {
  @Test("A sentence in bold is a headline over its paragraphs")
  func headline() {
    let layout = EntryLayout(
      .init(ordinal: 0, headline: "Sessions, per account.", body: ["Each one apart."]))
    #expect(layout.opening == "Sessions, per account.")
    #expect(layout.isHeadline)
    #expect(layout.details == ["Each one apart."])
  }

  @Test("A bold subject runs on into its sentence")
  func flowing() {
    let layout = EntryLayout(
      .init(ordinal: 0, headline: "Charts", body: [", now with stars.", "More."]))
    #expect(layout.opening == "**Charts**, now with stars.")
    #expect(!layout.isHeadline)
    #expect(layout.details == ["More."])
  }

  @Test("With no bold lead, the first paragraph is the point itself, not a grey detail")
  func noHeadline() {
    let layout = EntryLayout(.init(ordinal: 0, headline: nil, body: ["Shared trees are marked."]))
    #expect(layout.opening == "Shared trees are marked.")
    #expect(layout.details.isEmpty)
  }

  @Test("A section with no name has no badge")
  func unnamedSection() {
    #expect(ReleaseSectionLabel.label(for: "").isEmpty)
    #expect(!ReleaseSectionLabel.label(for: "Fixed").isEmpty)
  }
}
