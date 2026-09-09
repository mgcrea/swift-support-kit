import Foundation

extension Diagnostics {
  /// The block somebody pastes into an issue, a mail or a chat.
  ///
  ///     Silhouette 1.4 (168)
  ///     macOS 26.4 · Mac16,10 · en
  ///
  /// Plain text over two lines, not JSON and not a table: it lands in a GitHub
  /// issue body, a mail draft or a chat message, and all three render plain
  /// text and none of them render a table. The app and its version lead
  /// because that is the line a human reads; the machine facts follow on one
  /// line because nobody reads them until something is wrong.
  ///
  /// It carries the same four facts the feedback URL carries and no more. That
  /// is a rule rather than a coincidence — the copy button must not disclose
  /// anything the address bar would not have shown, which is the property that
  /// makes "you can see everything it sends" true here as well as on the web
  /// form.
  public func bugReportSummary(for app: SupportApp) -> String {
    """
    \(app.displayName) \(appVersion)
    \(osVersion) · \(hardware) · \(language)
    """
  }
}
