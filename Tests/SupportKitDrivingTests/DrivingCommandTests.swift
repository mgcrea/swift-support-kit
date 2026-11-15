import CoreGraphics
import Foundation
import Testing

@testable import SupportKitDriving

/// The wire format is the contract with Cupertino, which writes these lines. A
/// line it sends that parses to the wrong command drives the wrong thing, so
/// each verb is pinned from its literal line.
@Suite struct DrivingCommandTests {
  @Test func parsesAClick() throws {
    let envelope = try DrivingCommand.parse(
      line: #"{"seq":1,"verb":"click","x":10,"y":20,"button":"left","count":2}"#)
    #expect(envelope.seq == 1)
    #expect(envelope.command == .click(point: CGPoint(x: 10, y: 20), button: .left, count: 2))
  }

  /// A context menu is a window of its own, drawn over whatever the person is
  /// using, and its tracking loop does not read keys sent to the app's window,
  /// so nothing sent through the channel could close it. Refused, pointing at
  /// AXShowMenu, until that is measured.
  @Test func aRightClickIsRefusedNamingTheAlternative() {
    do {
      _ = try DrivingCommand.parse(line: #"{"seq":1,"verb":"click","x":1,"y":2,"button":"right"}"#)
      Issue.record("a right-click parsed")
    } catch {
      #expect("\(error)".contains("apple_desktop_show_menu"))
    }
  }

  @Test func aClickDefaultsToOneLeft() throws {
    let envelope = try DrivingCommand.parse(line: #"{"seq":2,"verb":"click","x":1,"y":2}"#)
    #expect(envelope.command == .click(point: CGPoint(x: 1, y: 2), button: .left, count: 1))
  }

  @Test func parsesADrag() throws {
    let envelope = try DrivingCommand.parse(
      line: #"{"seq":3,"verb":"drag","from":[1,2],"to":[30,40],"durationMs":250}"#)
    #expect(
      envelope.command
        == .drag(from: CGPoint(x: 1, y: 2), to: CGPoint(x: 30, y: 40), durationMs: 250))
  }

  /// A drag that says nothing more is what every caller sent before version 2: the left
  /// button, no modifier, its steps queued at once.
  @Test func aDragDefaultsToALeftQueuedDragWithNoModifier() throws {
    let envelope = try DrivingCommand.parse(
      line: #"{"seq":3,"verb":"drag","from":[1,2],"to":[30,40]}"#)
    #expect(
      envelope.command
        == .drag(
          from: CGPoint(x: 1, y: 2), to: CGPoint(x: 30, y: 40), durationMs: 300, button: .left,
          modifiers: [], paced: false))
  }

  /// The middle button and Option, as Maquette's viewport pans, sent in real time.
  @Test func parsesADragsButtonModifiersAndPacing() throws {
    let envelope = try DrivingCommand.parse(
      line:
        #"{"seq":3,"verb":"drag","from":[1,2],"to":[30,40],"durationMs":400,"button":"other","modifiers":["Option","shift"],"paced":true}"#
    )
    #expect(
      envelope.command
        == .drag(
          from: CGPoint(x: 1, y: 2), to: CGPoint(x: 30, y: 40), durationMs: 400, button: .other,
          modifiers: [.option, .shift], paced: true))
  }

  /// A right-press can open a context menu, which the channel could never close: refused on
  /// a drag for the reason it is on a click.
  @Test func aRightButtonDragIsRefused() {
    do {
      _ = try DrivingCommand.parse(
        line: #"{"seq":3,"verb":"drag","from":[1,2],"to":[3,4],"button":"right"}"#)
      Issue.record("a right-button drag parsed")
    } catch {
      #expect("\(error)".contains("context menu"))
    }
  }

  @Test func anUnknownButtonIsRefusedByName() {
    do {
      _ = try DrivingCommand.parse(
        line: #"{"seq":3,"verb":"drag","from":[1,2],"to":[3,4],"button":"middle"}"#)
      Issue.record("an unknown button parsed")
    } catch {
      #expect("\(error)".contains("middle"))
    }
  }

  @Test func anUnknownModifierOnADragIsRefused() {
    #expect(throws: DrivingCommand.ParseError.self) {
      try DrivingCommand.parse(
        line: #"{"seq":3,"verb":"drag","from":[1,2],"to":[3,4],"modifiers":["hyper"]}"#)
    }
  }

  /// `"paced":"true"` read as false would queue the drag the caller asked to pace, and say
  /// nothing.
  @Test func aPacingThatIsNotTrueOrFalseIsRefused() {
    #expect(throws: DrivingCommand.ParseError.self) {
      try DrivingCommand.parse(
        line: #"{"seq":3,"verb":"drag","from":[1,2],"to":[3,4],"paced":"true"}"#)
    }
  }

  /// Only a JSON boolean: `1` bridges to `true` through NSNumber, and is refused all the same.
  @Test func aPacingOfOneIsRefused() {
    #expect(throws: DrivingCommand.ParseError.self) {
      try DrivingCommand.parse(
        line: #"{"seq":3,"verb":"drag","from":[1,2],"to":[3,4],"paced":1}"#)
    }
    #expect(
      (try? DrivingCommand.parse(
        line: #"{"seq":3,"verb":"drag","from":[1,2],"to":[3,4],"paced":false}"#)) != nil)
  }

  /// A point past any display is refused when parsed: as a whole number of points it would
  /// trap converting to `Int`, and crash the app.
  @Test func aPointPastAnyDisplayIsRefused() {
    for line in [
      #"{"seq":1,"verb":"drag","from":[10,10],"to":[1e19,0]}"#,
      #"{"seq":1,"verb":"hover","x":5,"y":6,"from":[-1e19,0]}"#,
      #"{"seq":1,"verb":"click","x":1e19,"y":2}"#,
      #"{"seq":1,"verb":"scroll","x":1,"y":2000001,"dy":-1}"#,
    ] {
      #expect(throws: DrivingCommand.ParseError.self, "\(line)") {
        try DrivingCommand.parse(line: line)
      }
    }
    #expect(
      (try? DrivingCommand.parse(line: #"{"seq":1,"verb":"click","x":-5000,"y":3000}"#)) != nil)
  }

  /// The middle button is a drag's: a click takes the left one only.
  @Test func aClickWithTheOtherButtonIsRefused() {
    #expect(throws: DrivingCommand.ParseError.self) {
      try DrivingCommand.parse(line: #"{"seq":1,"verb":"click","x":1,"y":2,"button":"other"}"#)
    }
  }

  @Test func parsesAHover() throws {
    let envelope = try DrivingCommand.parse(
      line: #"{"seq":4,"verb":"hover","x":5,"y":6,"durationMs":0}"#)
    #expect(envelope.command == .hover(point: CGPoint(x: 5, y: 6), durationMs: 0))
  }

  /// Without `from`, as before version 2: every move at the point, with no delta.
  @Test func aHoverHasNoPathByDefault() throws {
    let envelope = try DrivingCommand.parse(line: #"{"seq":4,"verb":"hover","x":5,"y":6}"#)
    #expect(envelope.command == .hover(point: CGPoint(x: 5, y: 6), durationMs: 600, from: nil))
  }

  @Test func parsesAHoversPath() throws {
    let envelope = try DrivingCommand.parse(
      line: #"{"seq":4,"verb":"hover","x":5,"y":6,"from":[1,2],"durationMs":300}"#)
    #expect(
      envelope.command
        == .hover(point: CGPoint(x: 5, y: 6), durationMs: 300, from: CGPoint(x: 1, y: 2)))
  }

  @Test func aHoverFromThatIsNotAPairIsRefused() {
    #expect(throws: DrivingCommand.ParseError.self) {
      try DrivingCommand.parse(line: #"{"seq":4,"verb":"hover","x":5,"y":6,"from":[1]}"#)
    }
  }

  @Test func aScrollDefaultsToLines() throws {
    let envelope = try DrivingCommand.parse(
      line: #"{"seq":5,"verb":"scroll","x":5,"y":6,"dy":-3}"#)
    #expect(envelope.command == .scroll(point: CGPoint(x: 5, y: 6), dx: 0, dy: -3, units: .line))
  }

  @Test func parsesAPixelScroll() throws {
    let envelope = try DrivingCommand.parse(
      line: #"{"seq":5,"verb":"scroll","x":5,"y":6,"dx":4,"dy":-30,"units":"pixel"}"#)
    #expect(
      envelope.command == .scroll(point: CGPoint(x: 5, y: 6), dx: 4, dy: -30, units: .pixel))
  }

  @Test func anUnknownUnitIsRefusedByName() {
    do {
      _ = try DrivingCommand.parse(
        line: #"{"seq":5,"verb":"scroll","x":5,"y":6,"dy":-1,"units":"page"}"#)
      Issue.record("an unknown unit parsed")
    } catch {
      #expect("\(error)".contains("page"))
    }
  }

  @Test func parsesAScroll() throws {
    let envelope = try DrivingCommand.parse(
      line: #"{"seq":5,"verb":"scroll","x":5,"y":6,"dy":-3}"#)
    #expect(envelope.command == .scroll(point: CGPoint(x: 5, y: 6), dx: 0, dy: -3))
  }

  @Test func parsesTyping() throws {
    let envelope = try DrivingCommand.parse(line: #"{"seq":6,"verb":"type","text":"é ✓"}"#)
    #expect(envelope.command == .type(text: "é ✓"))
  }

  @Test func parsesAShortcut() throws {
    let envelope = try DrivingCommand.parse(
      line: #"{"seq":7,"verb":"key","key":"a","modifiers":["command","shift"]}"#)
    #expect(envelope.command == .key(name: "a", modifiers: [.command, .shift]))
  }

  @Test func aLineWithoutSeqIsRefused() {
    #expect(throws: DrivingCommand.ParseError.self) {
      try DrivingCommand.parse(line: #"{"verb":"type","text":"x"}"#)
    }
  }

  @Test func anUnknownVerbIsRefusedByName() {
    do {
      _ = try DrivingCommand.parse(line: #"{"seq":8,"verb":"tap","x":1,"y":2}"#)
      Issue.record("an unknown verb parsed")
    } catch {
      #expect("\(error)".contains("tap"))
    }
  }

  @Test func anUnknownModifierIsRefused() {
    #expect(throws: DrivingCommand.ParseError.self) {
      try DrivingCommand.parse(line: #"{"seq":9,"verb":"key","key":"a","modifiers":["hyper"]}"#)
    }
  }

  @Test func aClickWithoutAPointIsRefused() {
    #expect(throws: DrivingCommand.ParseError.self) {
      try DrivingCommand.parse(line: #"{"seq":10,"verb":"click"}"#)
    }
  }

  /// Positions, not letters: Return is 36 on every Mac, and `a` is the US
  /// position, which is what a shortcut's key equivalent is matched against.
  @Test func keyCodesArePositions() {
    #expect(DrivingCommand.keyCode("return") == 36)
    #expect(DrivingCommand.keyCode("escape") == 53)
    #expect(DrivingCommand.keyCode("a") == 0)
    #expect(DrivingCommand.keyCode("v") == 9)
    #expect(DrivingCommand.keyCode("nope") == nil)
  }

  /// Any single character is a key: a shortcut is matched by its characters,
  /// so Cmd-comma (Settings) needs no position, and code 0 carries it.
  @Test func aSingleCharacterIsAKey() {
    #expect(DrivingCommand.keyCode(",") == 0)
    #expect(DrivingCommand.keyCode("/") == 0)
  }

  /// Only a launch argument opens a channel: a default in the app's own domain
  /// or the global one would open it in every Debug build, every launch.
  @Test func onlyALaunchArgumentOpensAChannel() {
    #expect(Driving.requested(arguments: ["App", "-DrivingChannel", "YES"]))
    #expect(!Driving.requested(arguments: ["App"]))
    #expect(!Driving.requested(arguments: ["App", "-DrivingChannel", "NO"]))
    #expect(!Driving.requested(arguments: ["App", "-DrivingChannel"]))
  }
}
