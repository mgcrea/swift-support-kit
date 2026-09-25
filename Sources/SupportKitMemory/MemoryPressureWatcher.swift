import Dispatch

/// Calls back when macOS reports system memory pressure, so an app can hand
/// its caches back.
///
/// `MemoryBudget` bounds what an app may hold, but it is computed from the
/// machine's specs and so cannot know the one thing that decides whether the
/// machine stalls: what *else* is running. 80% of physical memory is a fair
/// share on an idle Mac and a greedy one next to a container VM, two simulators
/// and a PyTorch process. That changes minute to minute, which is why it is not
/// a preference either — a number the user sets once cannot track it. macOS
/// already publishes the signal, so react to it instead:
///
/// ```swift
/// MemoryPressureWatcher.start { _ in MLX.Memory.clearCache() }
/// ```
///
/// Drop caches here, not resident models. `clearCache()` frees only buffers
/// nothing is using; evicting the model itself turns a moment of system
/// pressure into a ten-second reload on the user's next click.
public enum MemoryPressureWatcher {
  public enum Level: Sendable, Equatable {
    case warning
    case critical
  }

  /// Held for the process lifetime: a dispatch source stops delivering once it
  /// is released, and there is no point in an app's life at which it would want
  /// to stop listening.
  @MainActor private static var source: DispatchSourceMemoryPressure?

  /// Whether the source is live. Exposed so the idempotence of `start` is
  /// testable.
  @MainActor public static var isWatching: Bool { source != nil }

  /// Start delivering pressure events to `handler`. Later calls are ignored and
  /// keep the first handler: replacing the source would drop the original's
  /// last reference, and a released source stops delivering with everything
  /// still looking wired up.
  ///
  /// The handler runs on a utility queue of its own, deliberately not the main
  /// one. MLX's `clearCache()` takes its eval lock and can block behind an
  /// in-flight forward pass; on the main thread that is a beachball at exactly
  /// the moment the machine is already struggling.
  @MainActor public static func start(_ handler: @escaping @Sendable (Level) -> Void) {
    guard source == nil else { return }
    let queue = DispatchQueue(label: "io.mgcrea.SupportKit.memory-pressure", qos: .utility)
    let watcher = DispatchSource.makeMemoryPressureSource(
      eventMask: [.warning, .critical], queue: queue)
    // Retains itself through the handler. Intentional: the source is never
    // cancelled, so there is nothing for the cycle to leak.
    watcher.setEventHandler {
      handler(watcher.data.contains(.critical) ? .critical : .warning)
    }
    watcher.resume()
    source = watcher
  }
}
