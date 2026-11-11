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
/// Points are global display points with a TOP-LEFT origin, the space every
/// Cupertino tool reads and writes; the app flips them itself.
public enum DrivingCommand: Equatable, Sendable {
  case click(point: CGPoint, button: Button, count: Int)
  case drag(from: CGPoint, to: CGPoint, durationMs: Int)
  case hover(point: CGPoint, durationMs: Int)
  case scroll(point: CGPoint, dx: Double, dy: Double)
  case type(text: String)
  case key(name: String, modifiers: [Modifier])

  public enum Button: String, Sendable {
    case left, right
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
    func point() throws -> CGPoint {
      guard let x = number("x"), let y = number("y") else {
        throw ParseError(description: "\(verb) needs x and y")
      }
      return CGPoint(x: x, y: y)
    }
    func pair(_ key: String) throws -> CGPoint {
      guard let values = object[key] as? [NSNumber], values.count == 2 else {
        throw ParseError(description: "\(verb) needs \(key) as [x, y]")
      }
      return CGPoint(x: values[0].doubleValue, y: values[1].doubleValue)
    }
    let durationMs = (object["durationMs"] as? NSNumber)?.intValue

    let command: DrivingCommand
    switch verb {
    case "click":
      let name = object["button"] as? String ?? "left"
      guard let button = Button(rawValue: name) else {
        throw ParseError(description: "unknown button \"\(name)\"")
      }
      command = .click(
        point: try point(), button: button,
        count: max(1, (object["count"] as? NSNumber)?.intValue ?? 1))
    case "drag":
      command = .drag(from: try pair("from"), to: try pair("to"), durationMs: durationMs ?? 300)
    case "hover":
      command = .hover(point: try point(), durationMs: durationMs ?? 600)
    case "scroll":
      command = .scroll(point: try point(), dx: number("dx") ?? 0, dy: number("dy") ?? 0)
    case "type":
      guard let text = object["text"] as? String else {
        throw ParseError(description: "type needs text")
      }
      command = .type(text: text)
    case "key":
      guard let name = object["key"] as? String else {
        throw ParseError(description: "key needs key")
      }
      let names = object["modifiers"] as? [String] ?? []
      let modifiers = try names.map { raw in
        guard let modifier = Modifier(rawValue: raw.lowercased()) else {
          throw ParseError(description: "unknown modifier \"\(raw)\"")
        }
        return modifier
      }
      command = .key(name: name.lowercased(), modifiers: modifiers)
    default:
      throw ParseError(description: "unknown verb \"\(verb)\"")
    }
    return Envelope(seq: seq, command: command)
  }

  /// A key's virtual key code: a POSITION, not a letter. The named keys are
  /// the ones Cupertino's `apple_desktop_key` knows, at the positions no layout
  /// moves. Letters and digits are their US positions, which is what an
  /// in-app shortcut is matched against once its characters are set from the
  /// name, so `command` + `a` selects all on any layout.
  public static func keyCode(_ name: String) -> UInt16? {
    named[name.lowercased()]
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
