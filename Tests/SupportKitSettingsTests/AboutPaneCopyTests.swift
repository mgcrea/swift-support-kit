import Foundation
import SupportKit
import Testing

@testable import SupportKitSettings

/// The copy button's payload, which is the one thing on the About pane that
/// leaves the machine.
///
/// SwiftUI bodies are not observable headlessly — the sidebar bug that shipped
/// in 1.1.0 passed every test in this package — so these assert the rule the
/// payload has to keep rather than what the pane draws.
@Suite("About pane copy payload")
struct AboutPaneCopyTests {
  private let app = SupportApp(
    slug: "example",
    displayName: "Example",
    siteURL: URL(string: "https://example.mgcrea.io")!
  )

  private let diagnostics = Diagnostics(
    appVersion: "1.4 (168)",
    osVersion: "macOS 26.4",
    hardware: "Mac16,10",
    language: "en"
  )

  @Test("the default payload is still the four-fact summary")
  func defaultPayloadIsTheSummary() {
    #expect(
      diagnostics.bugReportSummary(for: app) == """
        Example 1.4 (168)
        macOS 26.4 · Mac16,10 · en
        """)
  }

  /// `copySummary` exists so an app can add facts about the BUILD without the
  /// package widening `bugReportSummary` for everyone — that method's own doc
  /// comment makes the four-fact parity with the feedback URL a rule, and
  /// `DiagnosticsTests` enforces it. This checks the override is a genuine
  /// replacement rather than something appended to it.
  @Test("an override replaces the summary rather than extending it")
  func overrideReplaces() {
    let override = "Example 1.4 (168) · abc1234 · Developer ID · TEAMID"
    #expect(!override.contains(diagnostics.bugReportSummary(for: app)))
    #expect(override.contains("abc1234"))
  }
}
