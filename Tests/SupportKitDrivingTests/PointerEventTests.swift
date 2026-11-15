#if os(macOS) && DEBUG
  import AppKit
  import Testing

  @testable import SupportKitDriving

  /// The pointer events the channel makes, built without sending them. A canvas, a map or a
  /// 3D view moves by `deltaX`/`deltaY`, which `NSEvent.mouseEvent(with:…)` leaves at 0, so a
  /// drag that carries none moves nothing there.
  @Suite @MainActor struct PointerEventTests {
    /// A window never ordered in: it has a number, and nothing is drawn.
    func window() -> NSWindow {
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.borderless],
        backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      return window
    }

    @Test func aDragStepCarriesItsDeltaInPointsYDown() {
      let event = PointerEvent.make(
        .dragged, at: NSPoint(x: 10, y: 20), windowNumber: 0,
        delta: PointerEvent.Delta(dx: 7, dy: -3))
      #expect(event.type == .leftMouseDragged)
      #expect(event.deltaX == 7)
      #expect(event.deltaY == -3)
      #expect(event.locationInWindow == NSPoint(x: 10, y: 20))
    }

    /// The delta is set on the event's `CGEvent` and the `NSEvent` made again from it, which
    /// could have lost the window and the point in it. Measured: it keeps both, the
    /// timestamp too.
    @Test func theDeltaKeepsTheWindowItsPointAndTheTimestamp() {
      let window = window()
      defer { window.close() }
      let event = PointerEvent.make(
        .dragged, at: NSPoint(x: 10, y: 20), windowNumber: window.windowNumber,
        delta: PointerEvent.Delta(dx: 1, dy: 1), timestamp: 42.5)
      #expect(event.windowNumber == window.windowNumber)
      #expect(event.window === window)
      #expect(event.locationInWindow == NSPoint(x: 10, y: 20))
      #expect(event.timestamp == 42.5)
    }

    @Test func aClickAndAnUpCarryNoDelta() {
      for phase in [PointerEvent.Phase.down, .up] {
        let event = PointerEvent.make(phase, at: NSPoint(x: 1, y: 2), windowNumber: 0)
        #expect(event.deltaX == 0)
        #expect(event.deltaY == 0)
      }
    }

    @Test func theLeftButtonIsButtonZero() {
      let types = [PointerEvent.Phase.down, .dragged, .up].map {
        PointerEvent.make($0, button: .left, at: .zero, windowNumber: 0)
      }
      #expect(types.map(\.type) == [.leftMouseDown, .leftMouseDragged, .leftMouseUp])
      #expect(types.allSatisfy { $0.buttonNumber == 0 })
    }

    /// The middle button, which `otherMouseDown` and the rest carry as button 2.
    @Test func theOtherButtonIsTheMiddleOne() {
      let events = [PointerEvent.Phase.down, .dragged, .up].map {
        PointerEvent.make($0, button: .other, at: .zero, windowNumber: 0)
      }
      #expect(events.map(\.type) == [.otherMouseDown, .otherMouseDragged, .otherMouseUp])
      #expect(events.allSatisfy { $0.buttonNumber == 2 })
    }

    @Test func aMoveIsAMouseMoved() {
      let event = PointerEvent.make(
        .moved, at: .zero, windowNumber: 0, delta: PointerEvent.Delta(dx: -2, dy: 5))
      #expect(event.type == .mouseMoved)
      #expect(event.deltaX == -2)
      #expect(event.deltaY == 5)
    }

    @Test func modifiersAreCarried() {
      let flags = PointerEvent.flags([.option, .command])
      #expect(flags == [.option, .command])
      let event = PointerEvent.make(
        .dragged, button: .other, at: .zero, windowNumber: 0,
        delta: PointerEvent.Delta(dx: 1, dy: 0), flags: flags)
      #expect(event.modifierFlags.contains(.option))
      #expect(event.modifierFlags.contains(.command))
      #expect(!event.modifierFlags.contains(.shift))
    }

    @Test func theClickCountIsKept() {
      let event = PointerEvent.make(.down, at: .zero, windowNumber: 0, clickCount: 2)
      #expect(event.clickCount == 2)
    }

    /// Window points are y up and AppKit's deltas y down, so a step that goes down the
    /// window has a positive `dy`. Each delta is the movement from the step before, the
    /// first from where the path starts.
    @Test func aPathsDeltasAreTheMovementFromTheStepBefore() {
      let path = PointerEvent.path(
        from: NSPoint(x: 0, y: 100), to: NSPoint(x: 30, y: 40), steps: 3)
      #expect(
        path.map(\.point) == [NSPoint(x: 10, y: 80), NSPoint(x: 20, y: 60), NSPoint(x: 30, y: 40)])
      #expect(path.map(\.delta) == Array(repeating: PointerEvent.Delta(dx: 10, dy: 20), count: 3))
    }

    /// A `CGEvent`'s deltas are whole points (measured: 2.5 reads back as 2), so the steps
    /// share the rounding and their deltas add up to the whole movement.
    @Test func aPathsDeltasAddUpToTheWholeMovement() {
      let path = PointerEvent.path(
        from: NSPoint(x: 0.4, y: 0), to: NSPoint(x: 10.4, y: -7), steps: 4)
      #expect(path.map(\.delta.dx).reduce(0, +) == 10)
      #expect(path.map(\.delta.dy).reduce(0, +) == 7)
      #expect(path.last?.point == NSPoint(x: 10.4, y: -7))
    }

    @Test func aPathThatGoesNowhereHasNoDelta() {
      let point = NSPoint(x: 5, y: 6)
      let path = PointerEvent.path(from: point, to: point, steps: 24)
      #expect(path.count == 24)
      #expect(path.allSatisfy { $0.point == point && $0.delta == .zero })
    }

    /// A precise scroll, as a trackpad sends: `scrollingDeltaY` in points.
    @Test func aPixelScrollIsPrecise() throws {
      let window = window()
      defer { window.close() }
      let event = try #require(
        PointerEvent.scroll(
          at: NSPoint(x: 10, y: 20), windowNumber: window.windowNumber, dx: 4, dy: -30,
          units: .pixel))
      #expect(event.type == .scrollWheel)
      #expect(event.hasPreciseScrollingDeltas)
      #expect(event.scrollingDeltaY == -30)
      #expect(event.scrollingDeltaX == 4)
      #expect(event.window === window)
      #expect(event.locationInWindow == NSPoint(x: 10, y: 20))
    }

    /// A scroll made as a `CGEvent` at a screen point lost its window, and its point in the
    /// window was the screen point (measured, 2026-11-15): it is made from a mouse event for
    /// the window instead, and keeps both.
    @Test func aLineScrollIsNotPreciseAndKeepsItsWindow() throws {
      let window = window()
      defer { window.close() }
      let event = try #require(
        PointerEvent.scroll(
          at: NSPoint(x: 10, y: 20), windowNumber: window.windowNumber, dx: 2, dy: -3,
          units: .line))
      #expect(!event.hasPreciseScrollingDeltas)
      #expect(event.deltaY == -3)
      #expect(event.deltaX == 2)
      #expect(event.scrollingDeltaY == -3)
      #expect(event.window === window)
      #expect(event.locationInWindow == NSPoint(x: 10, y: 20))
    }

    /// A number past what a scroll wheel field holds is clamped, not a crash of the app.
    @Test func aHugeScrollIsClamped() throws {
      let event = try #require(
        PointerEvent.scroll(at: .zero, windowNumber: 0, dx: -1e12, dy: 1e12, units: .pixel))
      #expect(event.scrollingDeltaY == 1_000_000)
      #expect(event.scrollingDeltaX == -1_000_000)
    }

    /// Version 2 is what tells Cupertino the channel takes the fields above.
    @Test func theReadyEventSaysVersionTwo() throws {
      let channel = try DrivingChannel.open()
      defer { try? FileManager.default.removeItem(at: channel.directory) }
      channel.start { _ in }
      defer { channel.stop() }
      let text = try String(
        contentsOf: channel.directory.appendingPathComponent("events.jsonl"), encoding: .utf8)
      let line = try #require(text.split(separator: "\n").first)
      let ready = try #require(
        try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
      #expect(ready["kind"] as? String == "ready")
      #expect(ready["version"] as? Int == 2)
    }
  }
#endif
