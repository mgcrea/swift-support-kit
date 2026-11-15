#if os(macOS) && DEBUG
  import AppKit
  import SupportKitTestHost
  import Testing

  @testable import SupportKitDriving

  /// Commands sent through `EventSynthesis` to a real window, the test host's, which is
  /// ordered in past every display: nothing is drawn where anyone sees it, and the test
  /// process is an accessory app, never made active.
  ///
  /// `swift test` runs no `NSApp.run()`, so each test takes the app's events off the queue
  /// itself, as the app's own loop would, until the command is acknowledged: from a run-loop
  /// callout rather than from the test, and with the command delivered from a timer inside
  /// that loop. Measured, both: inside a test, which is a job on the main queue, the main
  /// queue is not drained again, so the pacing and the ack never ran; and the test process's
  /// own loop is the async main's `CFRunLoopRun`, which an event posted from a callout it ran
  /// directly (or while a test awaited) stopped, ending the whole run with exit 0.
  @Suite(.serialized) @MainActor struct PointerDeliveryTests {
    /// What a view was sent, when, and when it was done with it.
    struct Seen {
      var type: NSEvent.EventType
      var point: NSPoint
      var delta: CGVector
      var button: Int
      var flags: NSEvent.ModifierFlags
      /// When the event was made, which is when the channel sent it.
      var sent: TimeInterval
      var handled: TimeInterval
      var done: TimeInterval
      var precise = false
      var scrolled = CGVector.zero
    }

    final class RecordingView: NSView {
      var seen: [Seen] = []
      /// Holds the main thread this long inside the second drag step it is sent.
      var slowSecondStep: TimeInterval = 0
      /// Runs its own loop inside the mouse-down, pulling drags off the queue, as a slider
      /// does.
      var tracksInItsDown = false

      override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
      override var acceptsFirstResponder: Bool { true }

      func record(_ event: NSEvent) {
        let handled = ProcessInfo.processInfo.systemUptime
        let isDrag = event.type == .leftMouseDragged || event.type == .otherMouseDragged
        if isDrag, seen.filter({ $0.type == event.type }).count == 1, slowSecondStep > 0 {
          Thread.sleep(forTimeInterval: slowSecondStep)
        }
        var entry = Seen(
          type: event.type, point: event.locationInWindow,
          delta: CGVector(dx: event.deltaX, dy: event.deltaY), button: event.buttonNumber,
          flags: event.modifierFlags.intersection(.deviceIndependentFlagsMask),
          sent: event.timestamp, handled: handled, done: ProcessInfo.processInfo.systemUptime)
        if event.type == .scrollWheel {
          entry.precise = event.hasPreciseScrollingDeltas
          entry.scrolled = CGVector(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY)
        }
        seen.append(entry)
      }

      override func mouseDown(with event: NSEvent) {
        record(event)
        guard tracksInItsDown else { return }
        while let next = NSApp.nextEvent(
          matching: [.leftMouseDragged, .leftMouseUp], until: Date(timeIntervalSinceNow: 3),
          inMode: .eventTracking, dequeue: true)
        {
          record(next)
          if next.type == .leftMouseUp { break }
        }
      }
      override func mouseDragged(with event: NSEvent) { record(event) }
      override func mouseUp(with event: NSEvent) { record(event) }
      override func otherMouseDown(with event: NSEvent) { record(event) }
      override func otherMouseDragged(with event: NSEvent) { record(event) }
      override func otherMouseUp(with event: NSEvent) { record(event) }
      override func mouseMoved(with event: NSEvent) { record(event) }
      override func scrollWheel(with event: NSEvent) { record(event) }
    }

    let window: HostedWindow
    let view: RecordingView

    init() {
      NSApplication.shared.setActivationPolicy(.accessory)
      window = HostedWindow(
        contentRect: CGRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.borderless])
      view = RecordingView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
      window.contentView = view
      window.acceptsMouseEvents()
      window.orderFrontRegardless()
    }

    /// A point of the window, as Cupertino names it: global, top-left.
    func global(_ local: NSPoint) -> CGPoint {
      let screen = window.convertPoint(toScreen: local)
      return CGPoint(x: screen.x, y: (NSScreen.screens.first?.frame.height ?? 0) - screen.y)
    }

    /// Sends `command` and runs the app's event loop until it is acknowledged.
    func drive(_ command: DrivingCommand) async throws -> EventSynthesis.Ack {
      defer {
        window.orderOut(nil)
        window.close()
      }
      #expect(window.isVisible)
      #expect(!TestHost.isOnScreen(window))
      let outcome = await withCheckedContinuation { continuation in
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
          MainActor.assumeIsolated {
            continuation.resume(returning: Self.run(command))
          }
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
      }
      return try #require(outcome).get()
    }

    /// The app's loop, for one command, taking events off the queue until the command is
    /// acknowledged. The command is delivered from a timer that fires inside that loop, as
    /// the channel's poll delivers it inside `NSApp.run()`.
    static func run(_ command: DrivingCommand) -> Result<EventSynthesis.Ack, DrivingFailure>? {
      var outcome: Result<EventSynthesis.Ack, DrivingFailure>?
      let deliver = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent(), 0, 0, 0) {
        _ in
        MainActor.assumeIsolated { synthesis.perform(command) { outcome = $0 } }
      }
      CFRunLoopAddTimer(CFRunLoopGetMain(), deliver, .commonModes)
      let deadline = Date(timeIntervalSinceNow: 5)
      while outcome == nil, Date() < deadline {
        if let event = NSApp.nextEvent(
          matching: .any, until: Date(timeIntervalSinceNow: 0.002), inMode: .default,
          dequeue: true)
        {
          NSApp.sendEvent(event)
        }
      }
      return outcome
    }

    /// One for the whole run, as `Driving` holds one for the life of the app: each adds a
    /// monitor that takes the fences it queues, and one made per test was measured to take
    /// the next test's fences once it was gone, so that test's ack never came.
    static let synthesis = EventSynthesis()

    /// Every step and the up after the one before it was handled: each was made (and sent)
    /// once the view was done with the one before, even when the view held the main thread
    /// past the next step's time.
    func expectPaced(_ seen: [Seen]) {
      for (before, after) in zip(seen, seen.dropFirst()) {
        #expect(
          after.sent >= before.done, "\(after.type.rawValue) sent before the one before was done")
      }
    }

    /// The middle button with Option, as Maquette pans: each step carries its button, its
    /// modifier and its movement, and the steps go over the drag's duration.
    @Test func aPacedDragSendsEachStepOnceTheOneBeforeIsHandled() async throws {
      view.slowSecondStep = 0.08
      let ack = try await drive(
        .drag(
          from: global(NSPoint(x: 50, y: 50)), to: global(NSPoint(x: 150, y: 110)),
          durationMs: 200, button: .other, modifiers: [.option], paced: true))
      let seen = view.seen
      #expect(
        seen.map(\.type)
          == [.otherMouseDown] + Array(repeating: .otherMouseDragged, count: 8) + [.otherMouseUp])
      #expect(seen.allSatisfy { $0.button == 2 && $0.flags == .option })
      let drags = seen.filter { $0.type == .otherMouseDragged }
      // Up the window is up the screen: AppKit's deltas are y down.
      #expect(drags.map(\.delta.dx).reduce(0, +) == 100)
      #expect(drags.map(\.delta.dy).reduce(0, +) == -60)
      #expect(seen.first?.delta == .zero)
      #expect(seen.last?.delta == .zero)
      #expect(seen.last?.point == NSPoint(x: 150, y: 110))
      expectPaced(seen)
      let took = try #require(seen.last).handled - #require(seen.first).handled
      #expect(took >= 0.19, "the drag took \(took) s")
      #expect(ack.note == nil)
    }

    /// Without `paced`, as before version 2: every step and the up are queued before the
    /// down, so the drag takes no time. The steps carry their deltas all the same.
    @Test func aDragIsQueuedByDefault() async throws {
      _ = try await drive(
        .drag(
          from: global(NSPoint(x: 10, y: 10)), to: global(NSPoint(x: 40, y: 10)),
          durationMs: 100))
      let seen = view.seen
      #expect(
        seen.map(\.type)
          == [.leftMouseDown] + Array(repeating: .leftMouseDragged, count: 4) + [.leftMouseUp])
      let down = try #require(seen.first)
      #expect(seen.dropFirst().allSatisfy { $0.sent <= down.handled })
      #expect(seen.map(\.delta.dx) == [0, 8, 7, 8, 7, 0])
      #expect(seen.allSatisfy { $0.button == 0 && $0.flags.isEmpty })
    }

    /// A control that pulls the drags off the queue inside its down still gets each step in
    /// time, and the pacing still waits for it to take the one before.
    @Test func aPacedDragReachesAControlTrackingTheMouseInItsDown() async throws {
      view.tracksInItsDown = true
      view.slowSecondStep = 0.06
      _ = try await drive(
        .drag(
          from: global(NSPoint(x: 10, y: 10)), to: global(NSPoint(x: 10, y: 90)),
          durationMs: 100, paced: true))
      let seen = view.seen
      #expect(
        seen.map(\.type)
          == [.leftMouseDown] + Array(repeating: .leftMouseDragged, count: 4) + [.leftMouseUp])
      #expect(seen.map(\.delta.dy).reduce(0, +) == -80)
      expectPaced(seen)
      let took = try #require(seen.last).handled - #require(seen.first).handled
      #expect(took >= 0.09, "the drag took \(took) s")
    }

    /// With `from`, the moves go from it to the point, and say which way.
    @Test func aHoverMovesAlongItsPath() async throws {
      _ = try await drive(
        .hover(
          point: global(NSPoint(x: 34, y: 10)), durationMs: 0,
          from: global(NSPoint(x: 10, y: 10))))
      let moves = view.seen.filter { $0.type == .mouseMoved }
      #expect(moves.count == 24)
      #expect(moves.allSatisfy { $0.delta == CGVector(dx: 1, dy: 0) })
      #expect(moves.last?.point == NSPoint(x: 34, y: 10))
    }

    /// A trackpad's scroll reaches the view under its point, in a window off every display.
    @Test func aPixelScrollReachesTheViewUnderItsPoint() async throws {
      _ = try await drive(
        .scroll(point: global(NSPoint(x: 20, y: 30)), dx: 0, dy: -30, units: .pixel))
      let scroll = try #require(view.seen.first { $0.type == .scrollWheel })
      #expect(scroll.precise)
      #expect(scroll.scrolled.dy == -30)
      #expect(scroll.point == NSPoint(x: 20, y: 30))
    }
  }

  extension NSWindow {
    /// Moves are sent to a window only when it asks for them.
    fileprivate func acceptsMouseEvents() {
      acceptsMouseMovedEvents = true
      if let view = contentView { makeFirstResponder(view) }
    }
  }
#endif
