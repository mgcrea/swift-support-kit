#if os(macOS) && DEBUG
  import AppKit

  /// The file half of `Driving`: a directory in the app's own temporary
  /// directory, one file the agent appends commands to and one the app appends
  /// events to. Files rather than a socket or XPC because a sandboxed app can
  /// always write its own container, and the agent (Cupertino, which is not
  /// sandboxed) can read and write there; the same reason `AppShotCues` uses
  /// files.
  @MainActor
  final class DrivingChannel {
    let directory: URL
    private let commands: URL
    private let events: URL
    private var offset: UInt64 = 0
    private var buffer = Data()
    private var timer: Timer?

    static func open() throws -> DrivingChannel {
      let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("SupportKitDriving", isDirectory: true)
        .appendingPathComponent("\(getpid())", isDirectory: true)
      let files = FileManager.default
      try? files.removeItem(at: directory)
      try files.createDirectory(at: directory, withIntermediateDirectories: true)
      let channel = DrivingChannel(directory: directory)
      guard files.createFile(atPath: channel.commands.path, contents: nil),
        files.createFile(atPath: channel.events.path, contents: nil)
      else { throw CocoaError(.fileWriteUnknown) }
      return channel
    }

    private init(directory: URL) {
      self.directory = directory
      commands = directory.appendingPathComponent("commands.jsonl")
      events = directory.appendingPathComponent("events.jsonl")
    }

    /// Polls every 10 ms, in the common run-loop modes: a menu or a control
    /// tracking the mouse runs the loop in its tracking mode, and a timer in
    /// the default mode alone would stop reading until it ended.
    func start(_ handle: @escaping @MainActor (String) -> Void) {
      write(["kind": "ready", "pid": Int(getpid()), "version": 1])
      let timer = Timer(timeInterval: 0.01, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated { self?.poll(handle) }
      }
      RunLoop.main.add(timer, forMode: .common)
      self.timer = timer
      NotificationCenter.default.addObserver(
        forName: NSApplication.willTerminateNotification, object: nil, queue: .main
      ) { [directory] _ in try? FileManager.default.removeItem(at: directory) }
    }

    func write(_ event: [String: Any]) {
      guard var data = try? JSONSerialization.data(withJSONObject: event),
        let handle = try? FileHandle(forWritingTo: events)
      else { return }
      data.append(0x0A)
      defer { try? handle.close() }
      _ = try? handle.seekToEnd()
      try? handle.write(contentsOf: data)
    }

    private func poll(_ handle: @MainActor (String) -> Void) {
      guard let file = try? FileHandle(forReadingFrom: commands) else { return }
      defer { try? file.close() }
      guard (try? file.seek(toOffset: offset)) != nil,
        let chunk = try? file.readToEnd(), !chunk.isEmpty
      else { return }
      offset += UInt64(chunk.count)
      buffer.append(chunk)
      while let newline = buffer.firstIndex(of: 0x0A) {
        let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
        buffer.removeSubrange(buffer.startIndex...newline)
        if !line.trimmingCharacters(in: .whitespaces).isEmpty { handle(line) }
      }
    }
  }
#endif
