import Foundation
import Testing

@testable import SupportKit

// The cross-language contract, pinned.
//
// This URL is written here and read in `mgcrea-apps-feedback`, at
// `packages/feedback-contract/test/contract-golden.test.ts`. The two files
// assert the *same literal* from opposite ends: this one that Swift emits it,
// that one that TypeScript parses it back into the expected fields.
//
// ## Why a duplicated string is the right answer here
//
// The parameter names are a contract between two programs in two languages that
// ship from two repositories on independent schedules. SwiftPM resolves a
// package from its repository root and versions it by bare semver tags, so
// merging the two repos would hand the Swift package ownership of the root and
// the tag namespace — every Worker-only change would burn an SDK version or go
// untagged. The coupling is not worth that.
//
// What makes the duplication safe is that it lives in an *assertion* rather than
// in the code. Rename `av` on either side and a build goes red; the failure mode
// without this is silent, and the worst kind: the form still posts, the row
// still lands, and one column is simply empty for however long it takes someone
// to notice.
//
// **If you change this string, change it in both repositories in the same
// sitting**, and bump `contractVersion` if the shape changed rather than the
// example.
enum ContractGolden {
  /// Emitted by `feedbackURL` for `fixture` below. Byte-identical to the
  /// literal asserted in the contract package's TypeScript test.
  static let url =
    "https://silhouette.mgcrea.io/feedback/?v=1&app=silhouette&kind=bug"
    + "&av=1.4%20(168)&os=macOS%2026.4&hw=Mac16,10&lang=en"

  static let diagnostics = Diagnostics(
    appVersion: "1.4 (168)",
    osVersion: "macOS 26.4",
    hardware: "Mac16,10",
    language: "en"
  )

  static let app = SupportApp(
    slug: "silhouette",
    displayName: "Silhouette",
    siteURL: URL(string: "https://silhouette.mgcrea.io")!
  )
}

@Suite("Cross-language contract")
struct ContractGoldenTests {
  /// The whole point: not "the parameters are present" but "the string is
  /// exactly this". Parameter order is part of it, because the assertion on
  /// the other side is a string too.
  @Test("emits the golden URL byte for byte")
  func emitsGoldenURL() {
    let url = ContractGolden.app.feedbackURL(
      kind: .bug, diagnostics: ContractGolden.diagnostics)
    #expect(url.absoluteString == ContractGolden.url)
  }

  /// A guard on the encoding rules the other side depends on, stated
  /// separately so a failure says *which* rule broke rather than just
  /// "the string differs".
  @Test("encodes spaces as %20 and leaves the model's comma alone")
  func encodingRules() {
    let url = ContractGolden.app.feedbackURL(
      kind: .bug, diagnostics: ContractGolden.diagnostics
    ).absoluteString
    #expect(url.contains("av=1.4%20(168)"))
    #expect(url.contains("hw=Mac16,10"))
    #expect(!url.contains("+"))
  }

  /// The version travels as a bare integer. The receiving page compares it
  /// against its own constant, so a change in either type — say quoting it —
  /// would make every submission look like it came from an unknown version.
  @Test("sends the contract version as a bare integer")
  func versionIsBare() {
    #expect(ContractGolden.url.contains("?v=\(SupportApp.contractVersion)&"))
  }
}
