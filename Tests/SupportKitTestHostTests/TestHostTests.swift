#if os(macOS)
  import AppKit
  import Testing

  @testable import SupportKitTestHost

  @Suite("Test host")
  @MainActor
  struct TestHostTests {

    /// The variable XCTest sets in the process it loads a test bundle into, and only there.
    @Test func theEnvironmentNamesTheTestHost() {
      #expect(TestHost.isTestHost(environment: ["XCTestConfigurationFilePath": "/tmp/x"]))
      #expect(!TestHost.isTestHost(environment: [:]))
    }

    /// Only a Debug build under a test host opens nothing at launch.
    @Test func onlyATestHostSuppressesTheLaunchWindow() {
      #expect(!TestHost.suppressesLaunch(environment: [:]))
      #if DEBUG
        #expect(TestHost.suppressesLaunch(environment: ["XCTestConfigurationFilePath": "/x"]))
      #else
        #expect(!TestHost.suppressesLaunch(environment: ["XCTestConfigurationFilePath": "/x"]))
      #endif
    }

    #if DEBUG
      /// Past every display, so a window there intersects none.
      @Test func theOffscreenOriginIsOffEveryDisplay() {
        let frame = CGRect(
          origin: TestHost.offscreenOrigin, size: CGSize(width: 2000, height: 2000))
        #expect(NSScreen.screens.allSatisfy { !$0.frame.intersects(frame) })
      }

      /// Made off every screen, and AppKit's constraint back onto one is refused.
      @Test func aHostedWindowStartsOffEveryScreenAndStaysThere() {
        let window = HostedWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300))
        defer { window.close() }
        #expect(!TestHost.isOnScreen(window))
        #expect(!window.isReleasedWhenClosed)
        let asked = CGRect(x: 1e6, y: 1e6, width: 400, height: 300)
        #expect(window.constrainFrameRect(asked, to: NSScreen.screens.first) == asked)
      }

      /// A window on a display is moved off every screen; one already off is left alone.
      @Test func aWindowOnADisplayIsMovedOff() throws {
        let screen = try #require(NSScreen.screens.first)
        let window = NSWindow(
          contentRect: CGRect(origin: screen.frame.origin, size: CGSize(width: 300, height: 200)),
          styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        #expect(TestHost.isOnScreen(window))
        TestHost.keepOffscreen(window)
        #expect(!TestHost.isOnScreen(window))
        #expect(window.alphaValue == 1)
        let off = window.frame
        TestHost.keepOffscreen(window)
        #expect(window.frame == off)
      }
    #endif
  }
#endif
