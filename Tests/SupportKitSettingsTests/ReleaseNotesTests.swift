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
