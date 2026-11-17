import Foundation

#if os(macOS)
  import AppKit
#endif

/// Whether this copy of the app is a driven one, and what keeps it from touching the person's.
///
/// A driven copy is a Debug build launched beside the person's own copy of the app: Cupertino's
/// `apple_desktop_launch` with a `path` and `channel: true`. The two share the bundle id, so they
/// share the sandbox container, the preferences and the saved window state. Left alone, the
/// driven copy reopens the windows the person's copy saved, and saves its own over them, so the
/// person's next launch restores what an agent had open.
///
/// Two calls keep that apart:
///
///     // The App's init, before AppKit restores anything:
///     DrivenLaunch.prepare()
///
///     // applicationWillFinishLaunching:
///     DrivenLaunch.keepWindowsFromSaving()
///
/// Both do nothing unless the launch asked for the channel, and nothing in a Release build,
/// which has no channel. A person's copy and a test host behave exactly as without them.
///
/// The rest of what a driven copy must keep apart (its documents, its data, a server's port) is
/// the app's to decide, and `isRequestedAtLaunch` is what it asks. Written in Maquette first,
/// and moved here when Filiation needed the same.
public enum DrivenLaunch {
  /// The key AppKit reads at launch to skip restoring the windows it saved.
  public nonisolated static let ignoresSavedStateKey = "ApplePersistenceIgnoreState"

  /// Whether the arguments ask for the channel: `-DrivingChannel` followed by `YES`, `yes`,
  /// `true` or `1`. The arguments themselves, never `UserDefaults`; see `Driving`.
  public nonisolated static func isRequested(_ arguments: [String]) -> Bool {
    Driving.requested(arguments: arguments)
  }

  /// Whether this launch asked for the channel, read once from the arguments, whether or not
  /// the channel then opened. Always false in a Release build and on iOS, which have none.
  public nonisolated static let isRequestedAtLaunch: Bool = {
    #if os(macOS) && DEBUG
      isRequested(ProcessInfo.processInfo.arguments)
    #else
      false
    #endif
  }()

  /// Before AppKit restores anything: a driven copy registers `ApplePersistenceIgnoreState`,
  /// so it reopens none of the windows the shared container saved for the person's copy.
  ///
  /// Registered, never set: the registration domain lives only in this process, and a value
  /// set would persist in the preferences the person's copy reads too.
  public nonisolated static func prepare(
    arguments: [String] = ProcessInfo.processInfo.arguments,
    defaults: UserDefaults = .standard
  ) {
    #if os(macOS) && DEBUG
      guard isRequested(arguments) else { return }
      defaults.register(defaults: [ignoresSavedStateKey: true])
    #endif
  }

  #if os(macOS)
    /// A driven copy's windows save no state over the person's. Nothing for a launch that did
    /// not ask for the channel.
    @MainActor public static func keepFromSaving(
      _ windows: [NSWindow], requested: Bool = isRequestedAtLaunch
    ) {
      guard requested else { return }
      for window in windows where window.isRestorable { window.isRestorable = false }
    }

    /// From before the first window: every window of a driven launch is kept from saving after
    /// each pass of the event loop, whatever opened it (a document, a panel, Settings, About),
    /// before AppKit's deferred save of its state comes round.
    ///
    /// A window can still save once in the pass that opened it. A view that must be covered
    /// from its first moment calls `keepFromSaving([window])` as it enters its window, as
    /// Maquette's viewport does.
    @MainActor public static func keepWindowsFromSaving() {
      guard isRequestedAtLaunch, updates == nil else { return }
      updates = NotificationCenter.default.addObserver(
        forName: NSApplication.didUpdateNotification, object: nil, queue: .main
      ) { _ in
        MainActor.assumeIsolated { keepFromSaving(NSApp.windows) }
      }
    }

    /// The observer `keepWindowsFromSaving` installed, kept for the life of the process.
    @MainActor private static var updates: (any NSObjectProtocol)?
  #endif
}
