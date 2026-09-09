import Foundation
import Testing

@testable import SupportKit

@Suite("Bug report summary")
struct BugReportSummaryTests {
  private let app = SupportApp(
    slug: "silhouette",
    displayName: "Silhouette",
    siteURL: URL(string: "https://silhouette.mgcrea.io")!
  )
  private let fixture = Diagnostics(
    appVersion: "1.4 (168)",
    osVersion: "macOS 26.4",
    hardware: "Mac16,10",
    language: "en"
  )

  @Test("leads with the app and its version, machine facts second")
  func shape() {
    #expect(
      fixture.bugReportSummary(for: app) == """
        Silhouette 1.4 (168)
        macOS 26.4 · Mac16,10 · en
        """
    )
  }

  /// The rule that keeps the copy button honest: it must not disclose anything
  /// the address bar would not already have shown. Every fact here is a query
  /// parameter on the feedback URL, and there are no others.
  @Test("carries nothing the feedback URL does not")
  func disclosesNothingExtra() {
    let summary = fixture.bugReportSummary(for: app)
    let url = app.feedbackURL(kind: .bug, diagnostics: fixture).absoluteString

    for fact in [fixture.appVersion, fixture.osVersion, fixture.hardware, fixture.language] {
      #expect(summary.contains(fact))
    }
    // Nothing in the summary beyond the app's own name is absent from the URL.
    #expect(url.contains("av=1.4%20(168)"))
    #expect(url.contains("os=macOS%2026.4"))
    #expect(url.contains("hw=Mac16,10"))
    #expect(url.contains("lang=en"))
  }

  @Test("is two lines, so it pastes into an issue body unchanged")
  func twoLines() {
    #expect(fixture.bugReportSummary(for: app).split(separator: "\n").count == 2)
  }
}
