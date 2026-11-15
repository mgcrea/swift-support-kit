#if os(macOS) && DEBUG
  import AppKit

  /// The pointer events the channel sends, made for a window and testable without one.
  ///
  /// `NSEvent.mouseEvent(with:…)` takes no movement, so every event it makes has a `deltaX`
  /// and `deltaY` of 0, and a canvas, a map or a 3D view that moves by them moves nothing.
  /// Each event is made as before, then its `CGEvent` takes the delta (and the middle
  /// button's number, which the same call cannot take either) and the `NSEvent` is made again
  /// from it. Measured, 2026-11-15: the event made again keeps its window, its point in the
  /// window, its modifiers and its timestamp. A `CGEvent`'s deltas are whole points: 2.5 set
  /// as a double reads back as 2, and no public field holds a fraction.
  enum PointerEvent {
    enum Phase {
      case down, dragged, up, moved
    }

    /// A movement in whole points, y down as AppKit's deltas are.
    struct Delta: Equatable {
      var dx: Int
      var dy: Int
      static let zero = Delta(dx: 0, dy: 0)
    }

    /// Where a pointer is at one step of a path, and how it got there from the one before.
    struct Step: Equatable {
      var point: NSPoint
      var delta: Delta
    }

    static func type(_ phase: Phase, _ button: DrivingCommand.Button) -> NSEvent.EventType {
      switch (phase, button) {
      case (.moved, _): .mouseMoved
      case (.down, .left): .leftMouseDown
      case (.dragged, .left): .leftMouseDragged
      case (.up, .left): .leftMouseUp
      case (.down, .right): .rightMouseDown
      case (.dragged, .right): .rightMouseDragged
      case (.up, .right): .rightMouseUp
      case (.down, .other): .otherMouseDown
      case (.dragged, .other): .otherMouseDragged
      case (.up, .other): .otherMouseUp
      }
    }

    /// `local` is in the window's coordinates. A `windowNumber` of 0 makes an event for no
    /// window, whose point is then the one given.
    static func make(
      _ phase: Phase, button: DrivingCommand.Button = .left, at local: NSPoint,
      windowNumber: Int, delta: Delta = .zero, flags: NSEvent.ModifierFlags = [],
      clickCount: Int = 1, timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> NSEvent {
      let type = type(phase, button)
      let plain = NSEvent.mouseEvent(
        with: type, location: local, modifierFlags: flags, timestamp: timestamp,
        windowNumber: windowNumber, context: nil, eventNumber: 0, clickCount: clickCount,
        pressure: phase == .up ? 0 : 1)!
      guard let cg = plain.cgEvent else { return plain }
      cg.setIntegerValueField(.mouseEventDeltaX, value: Int64(delta.dx))
      cg.setIntegerValueField(.mouseEventDeltaY, value: Int64(delta.dy))
      if button == .other {
        cg.setIntegerValueField(
          .mouseEventButtonNumber, value: Int64(CGMouseButton.center.rawValue))
      }
      return NSEvent(cgEvent: cg) ?? plain
    }

    /// The points a pointer goes through from `start` to `end` in `steps` equal steps, the
    /// last at `end`, each with its movement from the one before (the first from `start`).
    ///
    /// Window points are y up, so a step down the window has a positive `dy`. The deltas
    /// are rounded from where the path started, not step by step, so they add up to the
    /// whole movement rounded: a view that sums them ends where the pointer did.
    static func path(from start: NSPoint, to end: NSPoint, steps: Int) -> [Step] {
      let count = max(1, steps)
      var previous = (x: 0, y: 0)
      return (1...count).map { step in
        let t = CGFloat(step) / CGFloat(count)
        let moved = (x: (end.x - start.x) * t, y: (end.y - start.y) * t)
        let whole = (x: Int(moved.x.rounded()), y: Int(moved.y.rounded()))
        defer { previous = whole }
        return Step(
          point: NSPoint(x: start.x + moved.x, y: start.y + moved.y),
          delta: Delta(dx: whole.x - previous.x, dy: -(whole.y - previous.y)))
      }
    }

    static func flags(_ modifiers: [DrivingCommand.Modifier]) -> NSEvent.ModifierFlags {
      var flags: NSEvent.ModifierFlags = []
      for modifier in modifiers {
        switch modifier {
        case .command: flags.insert(.command)
        case .shift: flags.insert(.shift)
        case .option: flags.insert(.option)
        case .control: flags.insert(.control)
        }
      }
      return flags
    }

    /// A scroll at `local` in the window: `line` units as a mouse's wheel, or `pixel`, a
    /// trackpad's precise scroll, whose `scrollingDeltaY` is in points. `dy` and `dx` are
    /// passed to the wheel as given, negative down as a `CGEvent` takes them.
    ///
    /// A scroll is a `CGEvent` (`NSEvent` makes none), and one made at a screen point found
    /// no window and kept the screen point as its point in the window (measured,
    /// 2026-11-15), so a window anywhere but the bottom left of the main display was
    /// scrolled somewhere else. So the scroll is made by CoreGraphics, which works out its
    /// line, point and fixed-point deltas, and those are copied onto a mouse event made for
    /// the window, retyped as a scroll: measured to read back the same deltas as
    /// CoreGraphics' own, with the window and the point.
    static func scroll(
      at local: NSPoint, windowNumber: Int, dx: Double, dy: Double,
      units: DrivingCommand.ScrollUnits,
      timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> NSEvent? {
      func wheel(_ value: Double) -> Int32 {
        Int32(max(-1_000_000, min(1_000_000, value)).rounded(.towardZero))
      }
      guard
        let made = CGEvent(
          scrollWheelEvent2Source: nil, units: units == .pixel ? .pixel : .line,
          wheelCount: 2, wheel1: wheel(dy), wheel2: wheel(dx), wheel3: 0),
        let cg = make(.moved, at: local, windowNumber: windowNumber, timestamp: timestamp)
          .cgEvent
      else { return nil }
      cg.type = .scrollWheel
      let whole: [CGEventField] = [
        .scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2,
        .scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2,
        .scrollWheelEventIsContinuous,
      ]
      for field in whole {
        cg.setIntegerValueField(field, value: made.getIntegerValueField(field))
      }
      for field: CGEventField in [
        .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2,
      ] {
        cg.setDoubleValueField(field, value: made.getDoubleValueField(field))
      }
      return NSEvent(cgEvent: cg)
    }
  }
#endif
