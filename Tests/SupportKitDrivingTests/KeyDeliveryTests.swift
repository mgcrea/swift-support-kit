#if os(macOS) && DEBUG
  import AppKit
  import Testing

  @testable import SupportKitDriving

  /// Shortcuts sent to the harness's window with a text field holding the focus, the field
  /// editor first responder, as in a SwiftUI dialog in Maquette, 2026-11-16: Cmd-Z there
  /// raised `NSInvalidArgumentException`, because the action was sent to the field editor by
  /// name, which does not implement it, and the channel answered nothing after it.
  ///
  /// In `PointerDeliveryTests`, so that they run serialized with the other tests that send
  /// through a real window, and on its rules (see its doc).
  extension PointerDeliveryTests {
    /// Implements the menu's actions, between the text field and the window: the field
    /// editor implements neither.
    final class ActingView: NSView {
      var shown = 0
      @objc func showBodies(_ sender: Any?) { shown += 1 }
      @objc func explode(_ sender: Any?) {
        NSException(name: .invalidArgumentException, reason: "the test's action raised").raise()
      }
    }

    /// A main menu as an app's: View ▸ Show Bodies on Option-Command-B, an item that raises
    /// on Option-Command-E, and Edit ▸ Undo on Command-Z, each with no target, so that the
    /// responder chain decides.
    static let mainMenu: NSMenu = {
      let main = NSMenu()
      for (menu, title, action, key, modifiers) in [
        ("View", "Show Bodies", #selector(ActingView.showBodies(_:)), "b", [.command, .option]),
        ("View", "Explode", #selector(ActingView.explode(_:)), "e", [.command, .option]),
        ("Edit", "Undo", Selector(("undo:")), "z", [.command]),
      ] as [(String, String, Selector, String, NSEvent.ModifierFlags)] {
        let holder =
          main.item(withTitle: menu)
          ?? {
            let holder = NSMenuItem(title: menu, action: nil, keyEquivalent: "")
            holder.submenu = NSMenu(title: menu)
            main.addItem(holder)
            return holder
          }()
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        holder.submenu?.addItem(item)
      }
      return main
    }()

    /// Makes `mainMenu` the app's, for the rest of the run: nothing else in it reads the main
    /// menu. Inside the loop `inTheLoop` runs, and with its events taken there, since setting
    /// it may post one (see the suite's doc).
    static func installTheMainMenu() async throws {
      try await inTheLoop {
        guard NSApp.mainMenu !== mainMenu else { return }
        NSApp.mainMenu = mainMenu
        takeEvents(until: Date(timeIntervalSinceNow: 0.05)) { false }
      }
    }

    /// A text field in an `ActingView`, with the focus, so the field editor is the window's
    /// first responder and the view is further up its chain.
    func focusATextField() throws -> ActingView {
      let acting = ActingView(frame: view.bounds)
      let field = NSTextField(frame: CGRect(x: 10, y: 10, width: 200, height: 24))
      acting.addSubview(field)
      view.addSubview(acting)
      #expect(window.makeFirstResponder(field))
      let editor = try #require(window.firstResponder as? NSTextView)
      #expect(editor.isFieldEditor)
      #expect(!editor.responds(to: #selector(ActingView.showBodies(_:))))
      return acting
    }

    /// The action goes up the responder chain from the field editor to the first responder
    /// that implements it, as AppKit sends a menu's action with no target.
    @Test func aShortcutWithATextFieldFocusedReachesTheResponderThatImplementsIt() async throws {
      let acting = try focusATextField()
      try await Self.installTheMainMenu()
      let ack = try await drive(.key(name: "b", modifiers: [.command, .option]))
      #expect(acting.shown == 1)
      #expect(ack.note == "menu item \"Show Bodies\"")
      #expect(ack.responder.contains("Text"), "\(ack.responder)")
    }

    /// Maquette's case: Edit ▸ Undo, `undo:` with no target, which the field editor does not
    /// implement and the window does. It undoes the typing, and the item is validated
    /// against the window, which retitles it with what it undoes: the title the ack names is
    /// Undo Typing, though nothing revalidates the main menu of an app that is not active.
    @Test func undoWithATextFieldFocusedReachesTheWindow() async throws {
      _ = try focusATextField()
      let editor = try #require(window.firstResponder as? NSTextView)
      editor.insertText("typed", replacementRange: editor.selectedRange())
      #expect(editor.string == "typed")
      try await Self.installTheMainMenu()
      #expect(!editor.responds(to: Selector(("undo:"))))
      let ack = try await drive(.key(name: "z", modifiers: [.command]))
      #expect(editor.string == "")
      #expect(ack.note == "menu item \"Undo Typing\"")
    }

    /// A command whose action raises answers an `error` naming the exception, and the
    /// channel goes on: the next command is acknowledged. Through the channel itself, since
    /// what stopped in Maquette was its poll: an exception out of a repeating timer's
    /// callout leaves the timer firing, and it never fires again.
    @Test func aCommandThatRaisesAnswersAnErrorAndTheChannelGoesOn() async throws {
      let acting = try focusATextField()
      try await Self.installTheMainMenu()
      defer {
        window.orderOut(nil)
        window.close()
      }
      DeliveryInFlight.value = true
      defer { DeliveryInFlight.value = false }
      let answered = try await Self.inTheLoop {
        try Self.throughAChannel([
          #"{"seq":1,"verb":"key","key":"e","modifiers":["command","option"]}"#,
          #"{"seq":2,"verb":"key","key":"b","modifiers":["command","option"]}"#,
        ])
      }
      let raised = try #require(answered[1])
      #expect(raised.kind == "error")
      let message = raised.message
      #expect(message.contains("NSInvalidArgumentException"), "\(message)")
      #expect(message.contains("the test's action raised"), "\(message)")
      let next = try #require(answered[2], "the channel answered nothing after the exception")
      #expect(next.kind == "ack")
      #expect(acting.shown == 1)
    }

    /// What the channel answered a command.
    struct Answer: Sendable {
      var kind: String
      var message: String
    }

    /// Opens a channel, sends it `lines` and takes the app's events off the queue until it
    /// has answered each, or for 5 s, then closes it: its answers by `seq`. All of it inside
    /// the loop `inTheLoop` runs, so that the channel's poll never fires in the test
    /// process's own loop (see the suite's doc).
    static func throughAChannel(_ lines: [String]) throws -> [Int: Answer] {
      let channel = try DrivingChannel.open()
      let driving = Driving(channel: channel)
      defer {
        channel.stop()
        try? FileManager.default.removeItem(at: channel.directory)
      }
      let commands = try FileHandle(
        forWritingTo: channel.directory.appendingPathComponent("commands.jsonl"))
      try commands.write(contentsOf: Data(lines.map { $0 + "\n" }.joined().utf8))
      try commands.close()
      let events = channel.directory.appendingPathComponent("events.jsonl")
      func answers() -> [Int: Answer] {
        let text = (try? String(contentsOf: events, encoding: .utf8)) ?? ""
        var answers: [Int: Answer] = [:]
        for line in text.split(separator: "\n") {
          guard
            let event = try? JSONSerialization.jsonObject(with: Data(line.utf8))
              as? [String: Any],
            let seq = event["seq"] as? Int
          else { continue }
          answers[seq] = Answer(
            kind: event["kind"] as? String ?? "", message: event["message"] as? String ?? "")
        }
        return answers
      }
      takeEvents(until: Date(timeIntervalSinceNow: 5)) { answers().count == lines.count }
      withExtendedLifetime(driving) {}
      return answers()
    }

    /// Takes the app's events off the queue, as its own loop would, until `done` or `deadline`.
    static func takeEvents(until deadline: Date, _ done: () -> Bool) {
      while !done(), Date() < deadline {
        if let event = NSApp.nextEvent(
          matching: .any, until: Date(timeIntervalSinceNow: 0.002), inMode: .default,
          dequeue: true)
        {
          NSApp.sendEvent(event)
        }
      }
    }

    /// Runs `body` from a run-loop callout, as `drive` runs a command.
    static func inTheLoop<T: Sendable>(
      _ body: @escaping @MainActor () throws -> T
    ) async throws -> T {
      let outcome = await withCheckedContinuation { continuation in
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
          MainActor.assumeIsolated { continuation.resume(returning: Result { try body() }) }
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
      }
      return try outcome.get()
    }
  }
#endif
