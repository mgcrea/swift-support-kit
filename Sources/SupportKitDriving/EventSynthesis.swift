#if os(macOS) && DEBUG
  import AppKit

  struct DrivingFailure: Error, CustomStringConvertible {
    let description: String
  }

  /// Turns a `DrivingCommand` into `NSEvent`s and hands them to this app's own
  /// windows, never to the session.
  ///
  /// What it relies on was measured in Cupertino's
  /// `scripts/spike-background-input.swift`, 2026-11-11: with the app inactive
  /// and its window in front or covered, `NSWindow.sendEvent` delivered keys to
  /// AppKit and SwiftUI fields, and clicks to AppKit and SwiftUI buttons, and the
  /// app never became active. A click needs its up QUEUED first, because
  /// NSButton's mouse-down runs a tracking loop that pulls the next mouse event
  /// off the queue and would otherwise wait for a real one.
  @MainActor
  final class EventSynthesis {
    struct Ack {
      var hit: String
      var identifier: String
      var responder: String
      var note: String?
    }

    typealias Done = (Result<Ack, DrivingFailure>) -> Void

    func perform(_ command: DrivingCommand, done: @escaping Done) {
      do {
        switch command {
        case .click(let point, let button, let count):
          try click(at: point, button: button, count: count, done: done)
        case .drag(let from, let to, let durationMs):
          try drag(from: from, to: to, steps: max(2, durationMs / 25), done: done)
        case .hover(let point, let durationMs):
          try hover(to: point, durationMs: durationMs, done: done)
        case .scroll(let point, let dx, let dy):
          try scroll(at: point, dx: dx, dy: dy, done: done)
        case .type(let text):
          try type(text, done: done)
        case .key(let name, let modifiers):
          try key(name, modifiers: modifiers, done: done)
        }
      } catch let failure as DrivingFailure {
        done(.failure(failure))
      } catch {
        done(.failure(DrivingFailure(description: "\(error)")))
      }
    }

    // ─── where an event goes ─────────────────────────────────────────────────

    /// The app's own window under a top-left global point, front to back, and
    /// the point in that window's coordinates.
    private func target(at point: CGPoint) throws -> (NSWindow, NSPoint) {
      let primary = NSScreen.screens.first?.frame.height ?? 0
      let cocoa = WindowPick.cocoa(point, primaryHeight: primary)
      let windows = NSApp.orderedWindows.filter(\.isVisible)
      guard
        let number = WindowPick.window(
          at: cocoa, in: windows.map { (number: $0.windowNumber, frame: $0.frame) }),
        let window = windows.first(where: { $0.windowNumber == number })
      else {
        throw DrivingFailure(
          description: "no window of this app at (\(Int(point.x)), \(Int(point.y)))")
      }
      return (window, window.convertPoint(fromScreen: cocoa))
    }

    /// Where keys go: the window that would be key if the app were active.
    private func keyTarget() throws -> NSWindow {
      if let window = NSApp.keyWindow ?? NSApp.mainWindow
        ?? NSApp.orderedWindows.first(where: \.isVisible)
      {
        return window
      }
      throw DrivingFailure(description: "this app has no visible window to type into")
    }

    private func ack(_ window: NSWindow, at local: NSPoint? = nil, note: String? = nil) -> Ack {
      var hitName = ""
      var identifier = ""
      if let local, let frame = window.contentView?.superview,
        let hit = frame.hitTest(local)
      {
        hitName = String(describing: Swift.type(of: hit))
        identifier = hit.accessibilityIdentifier()
      }
      let responder = window.firstResponder.map { String(describing: Swift.type(of: $0)) } ?? ""
      return Ack(hit: hitName, identifier: identifier, responder: responder, note: note)
    }

    /// One run-loop turn after the effect, so SwiftUI has applied it before the
    /// agent reads the screen back.
    private func finish(_ done: @escaping Done, _ ack: @escaping @MainActor () -> Ack) {
      DispatchQueue.main.async { MainActor.assumeIsolated { done(.success(ack())) } }
    }

    /// `finish`, but only once every event queued before it has been handled.
    ///
    /// A click QUEUES its up, and a SwiftUI button acts on the up, so the effect
    /// happens when the app's event loop reaches it, which can be after a plain
    /// `DispatchQueue.main.async`. Measured: an ack sent that way answered for a
    /// button whose action then held the main thread for 3 s. A marker event is
    /// queued behind the up, and the ack waits for it.
    private func finishAfterQueued(
      _ done: @escaping Done, _ ack: @escaping @MainActor () -> Ack
    ) {
      if fenceMonitor == nil {
        fenceMonitor = NSEvent.addLocalMonitorForEvents(matching: .applicationDefined) {
          [weak self] event in
          guard event.subtype.rawValue == Self.fenceSubtype else { return event }
          MainActor.assumeIsolated { self?.fences.removeValue(forKey: event.data1)?() }
          return nil
        }
      }
      nextFence += 1
      let token = nextFence
      fences[token] = { [weak self] in self?.finish(done, ack) }
      guard
        let marker = NSEvent.otherEvent(
          with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
          windowNumber: 0, context: nil, subtype: Self.fenceSubtype, data1: token, data2: 0)
      else {
        fences.removeValue(forKey: token)?()
        return
      }
      NSApp.postEvent(marker, atStart: false)
    }

    private static let fenceSubtype: Int16 = 0x5344
    private var fenceMonitor: Any?
    private var fences: [Int: @MainActor () -> Void] = [:]
    private var nextFence = 0

    // ─── the pointer ─────────────────────────────────────────────────────────

    private func mouse(
      _ type: NSEvent.EventType, _ window: NSWindow, _ local: NSPoint, clicks: Int = 1,
      flags: NSEvent.ModifierFlags = []
    ) -> NSEvent {
      NSEvent.mouseEvent(
        with: type, location: local, modifierFlags: flags,
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
        context: nil, eventNumber: 0, clickCount: clicks,
        pressure: type == .leftMouseUp || type == .rightMouseUp ? 0 : 1)!
    }

    private func click(
      at point: CGPoint, button: DrivingCommand.Button, count: Int, done: @escaping Done
    ) throws {
      let (window, local) = try target(at: point)
      switch button {
      case .left:
        for n in 1...count {
          NSApp.postEvent(mouse(.leftMouseUp, window, local, clicks: n), atStart: false)
          window.sendEvent(mouse(.leftMouseDown, window, local, clicks: n))
        }
        finishAfterQueued(done) { self.ack(window, at: local) }
      case .right:
        // Refused when parsed: see `DrivingCommand.parse`.
        throw DrivingFailure(description: "a right-click is not sent through the driving channel")
      }
    }

    /// The drags and the up are QUEUED before the down is sent, for the reason
    /// a click queues its up: a control that tracks the mouse (a slider, a
    /// split view) pulls them off the queue inside the down.
    private func drag(from: CGPoint, to: CGPoint, steps: Int, done: @escaping Done) throws {
      let (window, start) = try target(at: from)
      let primary = NSScreen.screens.first?.frame.height ?? 0
      let end = window.convertPoint(fromScreen: WindowPick.cocoa(to, primaryHeight: primary))
      for step in 1...steps {
        let t = CGFloat(step) / CGFloat(steps)
        let p = NSPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
        NSApp.postEvent(mouse(.leftMouseDragged, window, p), atStart: false)
      }
      NSApp.postEvent(mouse(.leftMouseUp, window, end), atStart: false)
      window.sendEvent(mouse(.leftMouseDown, window, start))
      finishAfterQueued(done) { self.ack(window, at: end) }
    }

    /// Not yet measured: whether a `mouseMoved` delivered this way fires a
    /// tracking area or SwiftUI's `onContinuousHover`, which the window server
    /// normally drives from the real cursor.
    private func hover(to point: CGPoint, durationMs: Int, done: @escaping Done) throws {
      let (window, local) = try target(at: point)
      let steps = 24
      let gap = Double(max(0, durationMs)) / 1000 / Double(steps)
      func step(_ n: Int) {
        window.sendEvent(mouse(.mouseMoved, window, local))
        if n < steps {
          DispatchQueue.main.asyncAfter(deadline: .now() + gap) {
            MainActor.assumeIsolated { step(n + 1) }
          }
        } else {
          finish(done) { self.ack(window, at: local, note: "hover is not yet measured") }
        }
      }
      step(1)
    }

    private func scroll(at point: CGPoint, dx: Double, dy: Double, done: @escaping Done) throws {
      let (window, local) = try target(at: point)
      guard
        let cg = CGEvent(
          scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: Int32(dy),
          wheel2: Int32(dx), wheel3: 0)
      else { throw DrivingFailure(description: "could not make a scroll event") }
      cg.location = point
      cg.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window.windowNumber))
      guard let event = NSEvent(cgEvent: cg) else {
        throw DrivingFailure(description: "could not make a scroll event")
      }
      window.sendEvent(event)
      finish(done) { self.ack(window, at: local, note: "scroll is not yet measured") }
    }

    // ─── the keyboard ────────────────────────────────────────────────────────

    private func keyEvent(
      _ type: NSEvent.EventType, _ window: NSWindow, characters: String, ignoring: String,
      code: UInt16, flags: NSEvent.ModifierFlags = []
    ) -> NSEvent {
      NSEvent.keyEvent(
        with: type, location: .zero, modifierFlags: flags,
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
        context: nil, characters: characters, charactersIgnoringModifiers: ignoring,
        isARepeat: false, keyCode: code)!
    }

    private func type(_ text: String, done: @escaping Done) throws {
      let window = try keyTarget()
      for character in text {
        let (characters, code): (String, UInt16) =
          switch character {
          case "\n", "\r": ("\r", 36)
          case "\t": ("\t", 48)
          default: (String(character), 0)
          }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
          window.sendEvent(
            keyEvent(type, window, characters: characters, ignoring: characters, code: code))
        }
      }
      finish(done) { self.ack(window) }
    }

    /// A shortcut is matched against the main menu and its item's action sent
    /// to this window's first responder by name. An app that is not active has
    /// no key window, so `NSApp.sendAction(_:to: nil)`, which is what a menu
    /// does with a key equivalent, would find no responder chain to walk.
    private func key(
      _ name: String, modifiers: [DrivingCommand.Modifier], done: @escaping Done
    ) throws {
      guard let code = DrivingCommand.keyCode(name) else {
        throw DrivingFailure(description: "unknown key \"\(name)\"")
      }
      let window = try keyTarget()
      var flags: NSEvent.ModifierFlags = []
      for modifier in modifiers {
        switch modifier {
        case .command: flags.insert(.command)
        case .shift: flags.insert(.shift)
        case .option: flags.insert(.option)
        case .control: flags.insert(.control)
        }
      }
      let characters = Self.characters(for: name)
      let shown = flags.contains(.shift) ? characters.uppercased() : characters

      if flags.contains(.command) || flags.contains(.control) {
        // Resolved from this window's first responder, as it would be if the
        // window were key, and validated against that target, so an item with
        // nothing to act on (Undo with nothing to undo) stays a no.
        if let item = Self.menuItem(in: NSApp.mainMenu, key: characters, flags: flags),
          let action = item.action,
          let target = NSApp.target(
            forAction: action, to: item.target ?? window.firstResponder ?? window, from: item)
        {
          if !Self.isUsable(item, target: target) {
            finish(done) {
              self.ack(window, note: "menu item \"\(item.title)\" is disabled; nothing was done")
            }
            return
          }
          if NSApp.sendAction(action, to: target, from: item) {
            finish(done) { self.ack(window, note: "menu item \"\(item.title)\"") }
            return
          }
        }
        let down = keyEvent(
          .keyDown, window, characters: shown, ignoring: characters, code: code, flags: flags)
        if window.performKeyEquivalent(with: down) {
          finish(done) { self.ack(window) }
          return
        }
      }
      for type in [NSEvent.EventType.keyDown, .keyUp] {
        window.sendEvent(
          keyEvent(type, window, characters: shown, ignoring: characters, code: code, flags: flags))
      }
      finish(done) { self.ack(window) }
    }

    /// Whether a matched item may run against `target`.
    ///
    /// A menu that does not enable its items automatically (a SwiftUI command
    /// menu, or one an app manages itself) means what `isEnabled` says. One that
    /// does is asked of the target, as AppKit's own validation would ask it from
    /// the key window, which an app in the background does not have.
    static func isUsable(_ item: NSMenuItem, target: Any) -> Bool {
      if item.menu?.autoenablesItems == false { return item.isEnabled }
      if let validating = target as? NSMenuItemValidation {
        return validating.validateMenuItem(item)
      }
      if let validating = target as? NSUserInterfaceValidations {
        return validating.validateUserInterfaceItem(item)
      }
      return true
    }

    /// The characters a named key produces, which is what AppKit matches a
    /// key equivalent and a text binding against.
    static func characters(for name: String) -> String {
      switch name {
      case "return", "enter": "\r"
      case "tab": "\t"
      case "space": " "
      case "delete": "\u{7F}"
      case "escape", "esc": "\u{1B}"
      case "left": String(UnicodeScalar(NSLeftArrowFunctionKey)!)
      case "right": String(UnicodeScalar(NSRightArrowFunctionKey)!)
      case "up": String(UnicodeScalar(NSUpArrowFunctionKey)!)
      case "down": String(UnicodeScalar(NSDownArrowFunctionKey)!)
      case "home": String(UnicodeScalar(NSHomeFunctionKey)!)
      case "end": String(UnicodeScalar(NSEndFunctionKey)!)
      case "pageup": String(UnicodeScalar(NSPageUpFunctionKey)!)
      case "pagedown": String(UnicodeScalar(NSPageDownFunctionKey)!)
      default: name
      }
    }

    /// The item whose key equivalent and modifiers match, searched depth first,
    /// as AppKit itself searches.
    ///
    /// Enabled or not: in an app that is not active, automatic validation finds
    /// no key window to resolve a nil target in and disables Select All, Copy
    /// and the rest. `key(_:modifiers:)` asks the explicit target instead.
    static func menuItem(in menu: NSMenu?, key: String, flags: NSEvent.ModifierFlags)
      -> NSMenuItem?
    {
      guard let menu else { return nil }
      let wanted = flags.intersection([.command, .shift, .option, .control])
      for item in menu.items {
        if let found = menuItem(in: item.submenu, key: key, flags: flags) { return found }
        guard !item.isSeparatorItem, !item.keyEquivalent.isEmpty else { continue }
        var mask = item.keyEquivalentModifierMask.intersection([
          .command, .shift, .option, .control,
        ])
        // An uppercase key equivalent carries its shift in the letter.
        if item.keyEquivalent != item.keyEquivalent.lowercased() { mask.insert(.shift) }
        if item.keyEquivalent.lowercased() == key.lowercased(), mask == wanted { return item }
      }
      return nil
    }
  }
#endif
