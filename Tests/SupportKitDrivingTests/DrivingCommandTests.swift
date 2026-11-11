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
      line: #"{"seq":1,"verb":"click","x":10,"y":20,"button":"right","count":2}"#)
    #expect(envelope.seq == 1)
    #expect(envelope.command == .click(point: CGPoint(x: 10, y: 20), button: .right, count: 2))
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

  @Test func parsesAHover() throws {
    let envelope = try DrivingCommand.parse(
      line: #"{"seq":4,"verb":"hover","x":5,"y":6,"durationMs":0}"#)
    #expect(envelope.command == .hover(point: CGPoint(x: 5, y: 6), durationMs: 0))
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
}
