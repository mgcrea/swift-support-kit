import Foundation

/// When a paced drag sends each of its events: its `steps` drags, then the up.
///
/// Step `k` of `n` (counted from 1) is due `k` × `durationMs` / `n` after the down, and the
/// up with the last step. An event goes at its time only once the app has taken the one
/// before off its queue, so a view that holds the main thread past the next step's time gets
/// the steps one after the other, never two queued together. If the one before is still not
/// taken after `patience`, the event goes anyway, and the ack says how many did: a drag
/// never leaves the app with a button held down.
///
/// Times are seconds since the down.
struct DragPacer: Equatable {
  let steps: Int
  let durationMs: Int

  static let patience: TimeInterval = 1
  /// How often a due event looks again for the one before it to be taken.
  static let poll: TimeInterval = 0.002

  enum Wait: Equatable {
    /// Send it. `unconfirmed` when the one before was still not taken after `patience`.
    case now(unconfirmed: Bool)
    /// Look again this many seconds later.
    case after(TimeInterval)
  }

  init(steps: Int, durationMs: Int) {
    self.steps = max(1, steps)
    self.durationMs = max(0, durationMs)
  }

  /// When event `index` is due: the steps are 0 to `steps` - 1, the up is `steps`.
  func due(_ index: Int) -> TimeInterval {
    Double(durationMs) / 1000 * Double(min(index + 1, steps)) / Double(steps)
  }

  /// What event `index` does at `elapsed`, given whether the one before was taken and when
  /// it was sent (nil for the first step, which follows the down).
  func wait(
    for index: Int, at elapsed: TimeInterval, previousTaken: Bool,
    previousSent: TimeInterval?
  ) -> Wait {
    let due = due(index)
    if elapsed < due { return .after(due - elapsed) }
    guard let sent = previousSent, !previousTaken else { return .now(unconfirmed: false) }
    if elapsed - sent >= Self.patience { return .now(unconfirmed: true) }
    return .after(Self.poll)
  }
}
