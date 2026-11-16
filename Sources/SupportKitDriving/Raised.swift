#if os(macOS) && DEBUG
  import Foundation
  import SupportKitDrivingCatch

  /// An `NSException` raised while the channel performs a command, stopped where the command
  /// is performed and answered as its error.
  ///
  /// Swift cannot catch one, and one that went on up out of the channel's poll, a repeating
  /// timer's callout, left that timer firing, so it never fired again: after Cmd-Z raised in
  /// Maquette, 2026-11-16, every later command went unanswered, though the app still ran.
  /// The `@try` is in `SupportKitDrivingCatch`, in Objective-C. The frames it unwinds are
  /// unwound as AppKit's own loop unwinds an event whose action raised, which is what the
  /// app does with an exception the person's own click or key raises.
  enum Raised {
    /// Runs `body`, and returns what it raised as the failure a command answers, or nil.
    static func catching(_ body: () -> Void) -> DrivingFailure? {
      guard let exception = SupportKitDrivingCatching(body) else { return nil }
      return failure(exception)
    }

    static func failure(_ exception: NSException) -> DrivingFailure {
      DrivingFailure(
        description: "raised \(exception.name.rawValue): \(exception.reason ?? "no reason given")")
    }
  }
#endif
