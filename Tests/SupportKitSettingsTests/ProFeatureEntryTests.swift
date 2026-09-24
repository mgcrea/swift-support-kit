import Testing

@testable import SupportKitSettings

private func entry(_ id: String, since: String?) -> ProFeatureEntry {
  ProFeatureEntry(id: id, title: "\(id)", systemImage: "star", since: since)
}

@Suite("Pro feature entries")
struct ProFeatureEntryTests {
  @Test("New for the whole minor it arrived in, and no longer")
  func newForItsMinor() {
    let feature = entry("batch", since: "1.4.0")
    #expect(feature.isNew(installedVersion: "1.4.0"))
    #expect(feature.isNew(installedVersion: "1.4.2"))
    #expect(!feature.isNew(installedVersion: "1.5.0"))
    #expect(!feature.isNew(installedVersion: "1.3.9"))
    #expect(!feature.isNew(installedVersion: "2.4.0"))
  }

  @Test("A feature with no version has always been in Pro")
  func launchFeaturesAreNeverNew() {
    #expect(!entry("export", since: nil).isNew(installedVersion: "1.0.0"))
  }

  @Test("This minor's additions come first, and the rest keep the app's order")
  func ordering() {
    let features = [
      entry("a", since: nil), entry("b", since: "1.2.0"), entry("c", since: "1.4.0"),
      entry("d", since: nil), entry("e", since: "1.4.1"),
    ]
    let ids = ProFeatureEntry.ordered(features, installedVersion: "1.4.1").map(\.id)
    #expect(ids == ["c", "e", "a", "b", "d"])
  }
}
