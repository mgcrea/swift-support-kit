#if os(macOS)
  import AppKit
  import SwiftUI

  /// The app as its hosted suite's host. `xcodebuild test` launches the app and loads the
  /// tests into it, on the Mac someone is working at: left a regular app, it opened its window
  /// over their work at launch, and every window a test opened was drawn there too. Under a
  /// test host it is an accessory app that opens nothing at launch and keeps every window it
  /// has off every display, so a run takes neither their screen nor their keyboard.
  ///
  /// ```swift
  /// // In the App's init, or the app delegate's applicationWillFinishLaunching:
  /// TestHost.stayInBackground()
  /// // On the scene that opens at launch:
  /// .defaultLaunchBehavior(TestHost.launchBehavior)
  /// ```
  ///
  /// Only a Debug build acts on it: a Release build is never a test host, and behaves the same
  /// whatever its environment.
  public enum TestHost {
    /// Whether this process is a test host: XCTest sets the variable in the process it loads
    /// a test bundle into.
    public static func isTestHost(
      environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
      environment["XCTestConfigurationFilePath"] != nil
    }

    /// Makes the app an accessory app and keeps its windows off every display, under a test
    /// host in a Debug build; otherwise does nothing. Call it before the app finishes
    /// launching. An accessory app has no Dock icon and is made active only when something
    /// asks; nothing here asks.
    @MainActor public static func stayInBackground() {
      #if DEBUG
        guard isTestHost(), !isStayingInBackground else { return }
        isStayingInBackground = true
        NSApplication.shared.setActivationPolicy(.accessory)
        let names = [
          NSWindow.didMoveNotification, NSWindow.didResizeNotification,
          NSWindow.didUpdateNotification, NSWindow.didChangeOcclusionStateNotification,
        ]
        for name in names {
          NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) {
            note in
            // AppKit posts these on the main thread, synchronously, from inside the move.
            nonisolated(unsafe) let window = note.object as? NSWindow
            MainActor.assumeIsolated { window.map(keepOffscreen) }
          }
        }
      #endif
    }

    /// What the scene that opens at launch opens: nothing under a test host in a Debug build,
    /// else what it always did. SwiftUI's own app delegate answers
    /// `applicationShouldOpenUntitledFile(_:)` without asking the app's, so the scene is
    /// where a document app's untitled document, or its Open panel, is stopped.
    public static var launchBehavior: SceneLaunchBehavior {
      suppressesLaunch() ? .suppressed : .automatic
    }

    static func suppressesLaunch(
      environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
      #if DEBUG
        isTestHost(environment: environment)
      #else
        false
      #endif
    }

    #if DEBUG
      @MainActor private static var isStayingInBackground = false

      /// Past the top right of every display, with room for the tallest window a test opens.
      @MainActor public static var offscreenOrigin: CGPoint {
        let all = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        return all.isNull ? .zero : CGPoint(x: all.maxX + 4000, y: all.maxY + 4000)
      }

      /// Whether any part of `window`'s frame is on a display.
      @MainActor public static func isOnScreen(_ window: NSWindow) -> Bool {
        NSScreen.screens.contains { $0.frame.intersects(window.frame) }
      }

      /// Moves a top-level window that is on a display off every screen.
      ///
      /// A test's own windows start there (`HostedWindow`), but SwiftUI moves a window back
      /// where it wants it after it is shown, and a document's window is AppKit's, which keeps
      /// 40 points of any titled window of its own on a display however far it is moved: that
      /// one goes as far as it will and is made transparent, letting clicks through. Sheets,
      /// popovers and their animations are drawn where their window is, centred on it, so a
      /// window off screen takes them with it; a window made transparent where it stood still
      /// showed its sheets sliding in. Called from inside the move, it puts the window back
      /// before anything is drawn. A test reads windows through their own coordinates and
      /// sends them its events directly, so none of this changes what it sees.
      @MainActor public static func keepOffscreen(_ window: NSWindow) {
        guard !window.isSheet, window.parent == nil, isOnScreen(window) else { return }
        window.setFrameOrigin(offscreenOrigin)
        if isOnScreen(window), window.alphaValue > 0 {
          window.alphaValue = 0
          window.ignoresMouseEvents = true
        }
      }
    #endif
  }
#endif
