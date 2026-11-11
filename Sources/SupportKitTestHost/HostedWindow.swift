#if os(macOS) && DEBUG
  import AppKit

  /// A hosted test's window, off every screen. A window a test orders front at the origin is
  /// drawn over the work of whoever is at the Mac, and AppKit moves a titled window back onto
  /// a screen when it is ordered in (`constrainFrameRect(_:to:)`), so this one refuses that and
  /// keeps its frame, past the top right of every display; under `TestHost.stayInBackground()`
  /// it is moved back there if anything else moves it. Everything else is a plain `NSWindow`:
  /// it is ordered front, takes a first responder and is sent events as before.
  ///
  /// An event made from a `CGEvent` at a point of the screen finds no window there, and its
  /// `locationInWindow` is then the screen point: make the event for its window with
  /// `NSEvent.mouseEvent(…windowNumber:…)` and set any field it cannot take on its `cgEvent`.
  public final class HostedWindow: NSWindow {
    public init(contentRect: CGRect, styleMask: NSWindow.StyleMask = [.titled]) {
      super.init(contentRect: contentRect, styleMask: styleMask, backing: .buffered, defer: false)
      isReleasedWhenClosed = false
      setFrameOrigin(TestHost.offscreenOrigin)
    }

    public override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
      frameRect
    }

    /// Shows `document`'s windows as File > New does, where no one sees them, in place of
    /// `showWindows()`. They are AppKit's windows, not `HostedWindow`s, so ordering one in
    /// constrains it back onto a screen: each is transparent from before it is shown, and
    /// `TestHost.keepOffscreen` moves it as far off as AppKit allows.
    public static func show(_ document: NSDocument) {
      if document.windowControllers.isEmpty { document.makeWindowControllers() }
      for window in document.windowControllers.compactMap(\.window) {
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.setFrameOrigin(TestHost.offscreenOrigin)
      }
      document.showWindows()
      for window in document.windowControllers.compactMap(\.window) {
        TestHost.keepOffscreen(window)
      }
    }

    /// A new untitled document, shown off every screen, in place of
    /// `openUntitledDocumentAndDisplay(true)`.
    public static func openUntitled() throws -> NSDocument {
      let document = try NSDocumentController.shared.openUntitledDocumentAndDisplay(false)
      show(document)
      return document
    }
  }
#endif
