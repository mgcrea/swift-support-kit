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
        case .drag(let from, let to, let durationMs, let button, let modifiers, let paced):
          try drag(
            from: from, to: to, durationMs: durationMs, button: button,
            flags: PointerEvent.flags(modifiers), paced: paced, done: done)
        case .hover(let point, let durationMs, let from):
          try hover(to: point, from: from, durationMs: durationMs, done: done)
        case .scroll(let point, let dx, let dy, let units):
          try scroll(at: point, dx: dx, dy: dy, units: units, done: done)
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

    /// A top-left global point in `window`'s coordinates, wherever it is.
    private func local(_ point: CGPoint, in window: NSWindow) -> NSPoint {
      let primary = NSScreen.screens.first?.frame.height ?? 0
      return window.convertPoint(fromScreen: WindowPick.cocoa(point, primaryHeight: primary))
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
      fence { [weak self] in self?.finish(done, ack) }
    }

    /// Queues a marker behind every event queued now, and calls `reached` when
    /// the app's own loop takes it, so once it has taken them all.
    private func fence(_ reached: @escaping @MainActor () -> Void) {
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
      fences[token] = reached
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

    private func click(
      at point: CGPoint, button: DrivingCommand.Button, count: Int, done: @escaping Done
    ) throws {
      let (window, local) = try target(at: point)
      switch button {
      case .left:
        let number = window.windowNumber
        for n in 1...count {
          NSApp.postEvent(
            PointerEvent.make(.up, at: local, windowNumber: number, clickCount: n), atStart: false)
          window.sendEvent(PointerEvent.make(.down, at: local, windowNumber: number, clickCount: n))
        }
        finishAfterQueued(done) { self.ack(window, at: local) }
      case .right, .other:
        // Refused when parsed: see `DrivingCommand.parse`.
        throw DrivingFailure(
          description: "a click is sent through the driving channel with the left button only")
      }
    }

    /// Unless `paced`, the drags and the up are QUEUED before the down is sent,
    /// for the reason a click queues its up: a control that tracks the mouse (a
    /// slider, a split view) pulls them off the queue inside the down. The drag
    /// then takes no time.
    ///
    /// Paced, step `k` of `n` is sent `k` × `durationMs` / `n` after the down,
    /// and the up as soon as the last step is taken; each only once the app has
    /// taken the one before off its queue, so a view that animates or throttles
    /// between events sees them one at a time. They are still queued, one at a
    /// time, so a control tracking the mouse inside its down takes them too.
    /// Taken means the fence queued behind it was reached (the app's own loop)
    /// or it is the current event (a control's tracking loop).
    private func drag(
      from: CGPoint, to: CGPoint, durationMs: Int, button: DrivingCommand.Button,
      flags: NSEvent.ModifierFlags, paced: Bool, done: @escaping Done
    ) throws {
      guard button != .right else {
        // Refused when parsed: see `DrivingCommand.parse`.
        throw DrivingFailure(description: "a right-button drag is not sent through the channel")
      }
      let (window, start) = try target(at: from)
      let end = local(to, in: window)
      let number = window.windowNumber
      let steps = max(2, durationMs / 25)
      let path = PointerEvent.path(from: start, to: end, steps: steps)
      /// Event `index`: a step, or the up after the last one. Made when it is
      /// sent, so its timestamp says when.
      func event(_ index: Int) -> NSEvent {
        guard index < path.count else {
          return PointerEvent.make(.up, button: button, at: end, windowNumber: number, flags: flags)
        }
        return PointerEvent.make(
          .dragged, button: button, at: path[index].point, windowNumber: number,
          delta: path[index].delta, flags: flags)
      }
      let count = path.count + 1
      let down = PointerEvent.make(
        .down, button: button, at: start, windowNumber: number, flags: flags)
      guard paced else {
        for index in 0..<count { NSApp.postEvent(event(index), atStart: false) }
        window.sendEvent(down)
        finishAfterQueued(done) { self.ack(window, at: end) }
        return
      }
      // Scheduled before the down is sent: a control tracking the mouse does
      // not return from it until the up, and the steps are sent from inside it.
      let pacer = DragPacer(steps: steps, durationMs: durationMs)
      let begin = ProcessInfo.processInfo.systemUptime
      var unconfirmed = 0
      var passed = Set<Int>()
      func send(_ index: Int, after previous: NSEvent?) {
        let wait = pacer.wait(
          for: index, at: ProcessInfo.processInfo.systemUptime - begin,
          previousTaken: previous.map { passed.contains(index - 1) || Self.isCurrent($0) } ?? true,
          previousSent: previous.map { $0.timestamp - begin })
        switch wait {
        case .now(let notTaken):
          if notTaken { unconfirmed += 1 }
          let sent = event(index)
          NSApp.postEvent(sent, atStart: false)
          fence { passed.insert(index) }
          if index + 1 < count {
            send(index + 1, after: sent)
          } else {
            let note =
              unconfirmed == 0
              ? nil
              : "paced: \(unconfirmed) of \(count) events were sent before the app had taken "
                + "the one before, after waiting \(Int(DragPacer.patience * 1000)) ms for it"
            finishAfterQueued(done) { self.ack(window, at: end, note: note) }
          }
        case .after(let seconds):
          DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            MainActor.assumeIsolated { send(index, after: previous) }
          }
        }
      }
      DispatchQueue.main.async { MainActor.assumeIsolated { send(0, after: nil) } }
      window.sendEvent(down)
    }

    /// Whether `event` is the one the app took last. A control tracking the
    /// mouse takes the drags off the queue and leaves the fence behind them
    /// there until its up, but it makes each drag it takes the current event.
    /// The current event alone would not do for the app's own loop: measured,
    /// an AppKit event it took after a step, stamped before it, replaced it.
    private static func isCurrent(_ event: NSEvent) -> Bool {
      guard let current = NSApp.currentEvent else { return false }
      return current.type == event.type && current.timestamp == event.timestamp
    }

    /// Not yet measured: whether a `mouseMoved` delivered this way fires a
    /// tracking area or SwiftUI's `onContinuousHover`, which the window server
    /// normally drives from the real cursor.
    private func hover(
      to point: CGPoint, from: CGPoint?, durationMs: Int, done: @escaping Done
    ) throws {
      let (window, end) = try target(at: point)
      let steps = 24
      let path = PointerEvent.path(
        from: from.map { local($0, in: window) } ?? end, to: end, steps: steps)
      let gap = Double(max(0, durationMs)) / 1000 / Double(steps)
      func step(_ n: Int) {
        window.sendEvent(
          PointerEvent.make(
            .moved, at: path[n - 1].point, windowNumber: window.windowNumber,
            delta: path[n - 1].delta))
        if n < steps {
          DispatchQueue.main.asyncAfter(deadline: .now() + gap) {
            MainActor.assumeIsolated { step(n + 1) }
          }
        } else {
          finish(done) { self.ack(window, at: end, note: "hover is not yet measured") }
        }
      }
      step(1)
    }

    private func scroll(
      at point: CGPoint, dx: Double, dy: Double, units: DrivingCommand.ScrollUnits,
      done: @escaping Done
    ) throws {
      let (window, local) = try target(at: point)
      guard
        let event = PointerEvent.scroll(
          at: local, windowNumber: window.windowNumber, dx: dx, dy: dy, units: units)
      else { throw DrivingFailure(description: "could not make a scroll event") }
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
      let flags = PointerEvent.flags(modifiers)
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
