import Foundation

#if os(macOS) && DEBUG
  import AppKit
#endif

/// Lets an agent drive this app without taking the Mac's focus.
///
/// An agent driving a Mac app the usual way posts clicks and keystrokes to the
/// login session, which has one cursor, one key window and one frontmost app,
/// so the app has to come to the front and the person at the keyboard loses
/// it. An iOS Simulator driven through WebDriverAgent does not, because its
/// events go into the simulated device. This is the same idea for an app we
/// build: the agent writes a command to a file, and the app delivers it to its
/// own windows as an `NSEvent`, so nothing reaches the session the person is
/// typing in and the app never becomes active.
///
/// **It compiles to nothing outside DEBUG.** An input channel inside an app
/// bypasses the Accessibility permission that guards every other way of
/// driving it: whoever can write the file can click anything in the app. So a
/// Release build has no channel, and a Debug build opens one only when launched
/// with `-DrivingChannel YES` (Cupertino's `apple_desktop_launch` with
/// `channel: true` passes it; an Xcode scheme can too).
///
///     // At launch, beside AppShotCues.start:
///     driving = Driving.startIfRequested()
///
/// Keep the returned object alive for the life of the process.
///
/// The channel is `<NSTemporaryDirectory()>/SupportKitDriving/<pid>/`, which
/// for a sandboxed app is inside its own container. `commands.jsonl` takes one
/// `DrivingCommand` line per command; `events.jsonl` gets `ready` once, then an
/// `ack` or an `error` for each command's `seq`.
@MainActor
public final class Driving {
  /// Nil unless this is a DEBUG build of a Mac app launched with
  /// `-DrivingChannel YES`.
  public static func startIfRequested() -> Driving? {
    #if os(macOS) && DEBUG
      guard UserDefaults.standard.bool(forKey: "DrivingChannel") else { return nil }
      do {
        return Driving(channel: try DrivingChannel.open())
      } catch {
        NSLog("SupportKitDriving: no channel: \(error)")
        return nil
      }
    #else
      return nil
    #endif
  }

  #if os(macOS) && DEBUG
    private let channel: DrivingChannel
    private let synthesis = EventSynthesis()

    private init(channel: DrivingChannel) {
      self.channel = channel
      channel.start { [weak self] line in self?.handle(line) }
    }

    private func handle(_ line: String) {
      let envelope: DrivingCommand.Envelope
      do {
        envelope = try DrivingCommand.parse(line: line)
      } catch {
        let seq =
          ((try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any])?["seq"]
          as? Int ?? -1
        channel.write(["kind": "error", "seq": seq, "message": "\(error)"])
        return
      }
      synthesis.perform(envelope.command) { [channel] outcome in
        switch outcome {
        case .success(let ack):
          var event: [String: Any] = [
            "kind": "ack", "seq": envelope.seq, "hit": ack.hit, "identifier": ack.identifier,
            "responder": ack.responder,
          ]
          if let note = ack.note { event["note"] = note }
          channel.write(event)
        case .failure(let error):
          channel.write(["kind": "error", "seq": envelope.seq, "message": error.description])
        }
      }
    }
  #endif
}
