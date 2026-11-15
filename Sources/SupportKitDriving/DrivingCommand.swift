import CoreGraphics
import Foundation

/// One thing a driving agent asks the app to do, as it arrives on the channel.
///
/// The wire format is one JSON object per line, written by Cupertino:
///
///     {"seq":1,"verb":"click","x":10,"y":20,"button":"left","count":1}
///     {"seq":2,"verb":"drag","from":[1,2],"to":[30,40],"durationMs":250}
///     {"seq":3,"verb":"hover","x":5,"y":6,"durationMs":600}
///     {"seq":4,"verb":"scroll","x":5,"y":6,"dx":0,"dy":-3}
///     {"seq":5,"verb":"type","text":"hello"}
///     {"seq":6,"verb":"key","key":"a","modifiers":["command"]}
///
/// Version 2 of the channel (its `ready` event says which) adds optional fields,
/// each defaulting to what version 1 did:
///
///     {"seq":7,"verb":"drag","from":[1,2],"to":[30,40],"durationMs":400,
///      "button":"other","modifiers":["option"],"paced":true}
///     {"seq":8,"verb":"hover","x":5,"y":6,"from":[1,2],"durationMs":300}
///     {"seq":9,"verb":"scroll","x":5,"y":6,"dy":-30,"units":"pixel"}
///
/// Points are global display points with a TOP-LEFT origin, the space every
/// Cupertino tool reads and writes; the app flips them itself. A point past
/// ±`maxCoordinate` on either axis is refused.
public enum DrivingCommand: Equatable, Sendable {
  case click(point: CGPoint, button: Button, count: Int)
  /// `button` is `left` or `other` (the middle button), and `modifiers` are held
  /// on the down, every step and the up. Unless `paced`, every step and the up
  /// are queued before the down, so the drag takes no time; `paced` sends each
  /// step at its time over `durationMs`, once the app has taken the one before,
  /// and ends within `durationMs` plus a second if the app takes nothing.
  case drag(
    from: CGPoint, to: CGPoint, durationMs: Int, button: Button = .left,
    modifiers: [Modifier] = [], paced: Bool = false)
  /// With `from`, the moves go from it to `point`, and their deltas say which
  /// way; without it, every move is at `point`.
  case hover(point: CGPoint, durationMs: Int, from: CGPoint? = nil)
  /// `line` units, as a mouse's wheel sends, or `pixel`, a trackpad's precise
  /// scroll.
  case scroll(point: CGPoint, dx: Double, dy: Double, units: ScrollUnits = .line)
  case type(text: String)
  case key(name: String, modifiers: [Modifier])

  /// `other` is the middle button. Only a drag takes it.
  public enum Button: String, Sendable {
    case left, right, other
  }

  public enum ScrollUnits: String, Sendable {
    case line, pixel
  }

  public enum Modifier: String, Sendable {
    case command, shift, option, control
  }

  public struct Envelope: Equatable, Sendable {
    public let seq: Int
    public let command: DrivingCommand
  }

  public struct ParseError: Error, CustomStringConvertible, Sendable {
    public let description: String
  }

  public static func parse(line: String) throws -> Envelope {
    guard
      let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
    else { throw ParseError(description: "not a JSON object: \(line)") }
    guard let seq = (object["seq"] as? NSNumber)?.intValue else {
      throw ParseError(description: "no seq: \(line)")
    }
    let verb = object["verb"] as? String ?? ""

    func number(_ key: String) -> Double? { (object[key] as? NSNumber)?.doubleValue }
    // A point past any display would trap where the app makes it a whole
    // number of points (a drag's deltas, a message naming it), so it is
    // refused here, for every verb.
    func onSomeDisplay(_ point: CGPoint, _ name: String) throws -> CGPoint {
      guard abs(point.x) <= maxCoordinate, abs(point.y) <= maxCoordinate else {
        throw ParseError(
          description:
            "\(verb)'s \(name) is past any display: coordinates are within "
            + "±\(Int(maxCoordinate)) points")
      }
      return point
    }
    func point() throws -> CGPoint {
      guard let x = number("x"), let y = number("y") else {
        throw ParseError(description: "\(verb) needs x and y")
      }
      return try onSomeDisplay(CGPoint(x: x, y: y), "point")
    }
    func pair(_ key: String) throws -> CGPoint {
      guard let values = object[key] as? [NSNumber], values.count == 2 else {
        throw ParseError(description: "\(verb) needs \(key) as [x, y]")
      }
      return try onSomeDisplay(
        CGPoint(x: values[0].doubleValue, y: values[1].doubleValue), key)
    }
    let durationMs = (object["durationMs"] as? NSNumber)?.intValue
    func pointerButton() throws -> Button {
      let name = object["button"] as? String ?? "left"
      guard let button = Button(rawValue: name) else {
        throw ParseError(description: "unknown button \"\(name)\"")
      }
      return button
    }
    func modifierList() throws -> [Modifier] {
      let names = object["modifiers"] as? [String] ?? []
      return try names.map { raw in
        guard let modifier = Modifier(rawValue: raw.lowercased()) else {
          throw ParseError(description: "unknown modifier \"\(raw)\"")
        }
        return modifier
      }
    }

    let command: DrivingCommand
    switch verb {
    case "click":
      let button = try pointerButton()
      // A context menu is a window of its own, drawn over whatever the person
      // is using, and its tracking loop reads no key sent to the app's window,
      // so nothing sent here could close it. Not measured, so refused.
      switch button {
      case .left: break
      case .right:
        throw ParseError(
          description:
            "a right-click is not sent through the driving channel: the menu it opens would "
            + "stay over the person's work with no way to close it from here. Use "
            + "apple_desktop_show_menu on the element instead")
      case .other:
        throw ParseError(
          description: "a click is sent with the left button only; \"other\" is a drag's")
      }
      command = .click(
        point: try point(), button: button,
        count: max(1, (object["count"] as? NSNumber)?.intValue ?? 1))
    case "drag":
      let button = try pointerButton()
      // A right-press opens a context menu as a right-click does, for the same
      // reason refused.
      guard button != .right else {
        throw ParseError(
          description:
            "a right-button drag is not sent through the driving channel: the context menu a "
            + "right-press can open would stay over the person's work with no way to close it "
            + "from here")
      }
      var paced = false
      if let raw = object["paced"] {
        // A JSON boolean only: NSNumber bridges `1` to true as well.
        guard CFGetTypeID(raw as CFTypeRef) == CFBooleanGetTypeID(), let value = raw as? Bool
        else { throw ParseError(description: "paced is true or false") }
        paced = value
      }
      command = .drag(
        from: try pair("from"), to: try pair("to"), durationMs: durationMs ?? 300,
        button: button, modifiers: try modifierList(), paced: paced)
    case "hover":
      command = .hover(
        point: try point(), durationMs: durationMs ?? 600,
        from: object["from"] == nil ? nil : try pair("from"))
    case "scroll":
      let name = object["units"] as? String ?? "line"
      guard let units = ScrollUnits(rawValue: name) else {
        throw ParseError(description: "unknown units \"\(name)\", line or pixel")
      }
      command = .scroll(
        point: try point(), dx: number("dx") ?? 0, dy: number("dy") ?? 0, units: units)
    case "type":
      guard let text = object["text"] as? String else {
        throw ParseError(description: "type needs text")
      }
      command = .type(text: text)
    case "key":
      guard let name = object["key"] as? String else {
        throw ParseError(description: "key needs key")
      }
      command = .key(name: name.lowercased(), modifiers: try modifierList())
    default:
      throw ParseError(description: "unknown verb \"\(verb)\"")
    }
    return Envelope(seq: seq, command: command)
  }

  /// How far from the main display's origin a point may be, in points: past
  /// any arrangement of displays, and well inside what a whole number holds.
  static let maxCoordinate: Double = 1_000_000

  /// A key's virtual key code: a POSITION, not a letter. The named keys are
  /// the ones Cupertino's `apple_desktop_key` knows, at the positions no layout
  /// moves. Letters and digits are their US positions, which is what an
  /// in-app shortcut is matched against once its characters are set from the
  /// name, so `command` + `a` selects all on any layout.
  public static func keyCode(_ name: String) -> UInt16? {
    // Any other single character is matched by its characters, which is all a
    // menu's key equivalent and a text binding look at, so code 0 carries it.
    named[name.lowercased()] ?? (name.count == 1 ? 0 : nil)
  }

  private static let named: [String: UInt16] = {
    var codes: [String: UInt16] = [
      "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53, "esc": 53,
      "left": 123, "right": 124, "down": 125, "up": 126,
      "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
      "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
    ]
    let letters: [(String, UInt16)] = [
      ("a", 0), ("s", 1), ("d", 2), ("f", 3), ("h", 4), ("g", 5), ("z", 6), ("x", 7),
      ("c", 8), ("v", 9), ("b", 11), ("q", 12), ("w", 13), ("e", 14), ("r", 15), ("y", 16),
      ("t", 17), ("1", 18), ("2", 19), ("3", 20), ("4", 21), ("6", 22), ("5", 23), ("9", 25),
      ("7", 26), ("8", 28), ("0", 29), ("o", 31), ("u", 32), ("i", 34), ("p", 35), ("l", 37),
      ("j", 38), ("k", 40), ("n", 45), ("m", 46),
    ]
    for (name, code) in letters { codes[name] = code }
    return codes
  }()
}
