import CryptoKit
import Foundation
import Synchronization

public enum InstallProgress: Equatable, Sendable {
  case downloading(received: Int64, total: Int64)
  /// Hashing a file that just arrived.
  case verifying
  case compiling
}

/// Why an install failed. The descriptions are plain English and name no app; an app that
/// words them differently, or localizes them, passes its own `describe` to
/// `ModelInstallStore`.
public enum ModelInstallError: Error, Equatable, LocalizedError {
  case network(String)
  /// A non-2xx answer other than 404.
  case httpStatus(Int)
  /// A file whose size or hash is not what the registry pins, or that is missing (404) at the
  /// pinned revision or URL. Names the file and where it came from, which is where the fix
  /// starts.
  case fileMismatch(path: String, repo: String)
  case diskFull
  case unpackFailed(String)
  case noModelInArchive
  case compileFailed(String)

  public var errorDescription: String? {
    switch self {
    case .network(let detail):
      "The download failed: \(detail). Check your connection and try again."
    case .httpStatus(let status):
      "The download failed with HTTP \(status)."
    case .fileMismatch(let path, let repo):
      "\(path) from \(repo) isn't the expected file. The source may have changed; try again, "
        + "or update the app."
    case .diskFull:
      "There isn't enough disk space. Free up some space and try again."
    case .unpackFailed(let detail):
      "The download couldn't be unpacked: \(detail)."
    case .noModelInArchive:
      "No .mlpackage or .mlmodel was found inside the downloaded archive."
    case .compileFailed(let detail):
      "The model downloaded but couldn't be prepared: \(detail)."
    }
  }
}

/// Downloads a model's files one by one into its staging folder, checks each file's size and
/// SHA-256 against the registry, turns them into the finished model (compiled, unpacked and
/// compiled, or kept as is) and moves it into place. Anything that stops it (an error or
/// cancellation) deletes the staging folder, so a model is either fully installed or not
/// there at all, and the previously installed version is untouched until the new one is.
public struct ModelInstaller: Sendable {
  public let locations: ModelLocations
  private let fetcher: any FileFetcher
  private let compiler: any ModelCompiler
  private let unpacker: (any ArchiveUnpacker)?

  public init(
    locations: ModelLocations, fetcher: any FileFetcher = URLSessionFetcher(),
    compiler: any ModelCompiler = CoreMLCompiler(), unpacker: (any ArchiveUnpacker)? = nil
  ) {
    self.locations = locations
    self.fetcher = fetcher
    self.compiler = compiler
    self.unpacker = unpacker
  }

  /// Returns the finished model's URL, `locations.artifact(of: package)`. `@concurrent` so
  /// hashing hundreds of megabytes never runs on the caller's actor.
  @concurrent
  public func install(
    _ package: ModelPackage, progress: @escaping @Sendable (InstallProgress) -> Void
  ) async throws -> URL {
    let files = FileManager.default
    let staging = locations.staging(for: package.id)
    try? files.removeItem(at: staging)
    do {
      try Self.mappingDiskFull {
        try locations.createRoot()
        try files.createDirectory(at: staging, withIntermediateDirectories: true)
      }
      let total = package.totalBytes
      let gate = ProgressGate(total: total)
      var done: Int64 = 0
      progress(.downloading(received: 0, total: total))
      for file in package.files {
        try Task.checkCancellation()
        let base = done
        let temporary = try await fetch(file, of: package) { received in
          if gate.admit(base + received) {
            progress(.downloading(received: base + received, total: total))
          }
        }
        let destination = staging.appending(path: file.path)
        try Self.mappingDiskFull {
          try files.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
          try files.moveItem(at: temporary, to: destination)
        }
        done += file.bytes
        gate.reset(to: done)
        progress(.downloading(received: done, total: total))
        // After the byte count, not before it: a last file reporting its bytes once more
        // after the hash would show "downloading" again between "verifying" and the end.
        progress(.verifying)
        try Self.verify(destination, against: file, repo: package.repository)
      }
      try Task.checkCancellation()
      let finished = try await finish(package, in: staging, progress: progress)
      let target = locations.artifact(of: package)
      try? files.removeItem(at: target)
      try Self.mappingDiskFull { try files.moveItem(at: finished, to: target) }
      Self.removeEverything(in: locations.folder(for: package.id), except: target)
      return target
    } catch {
      try? files.removeItem(at: staging)
      throw error
    }
  }

  /// Turns the verified files in `staging` into the model to move into place.
  private func finish(
    _ package: ModelPackage, in staging: URL,
    progress: @escaping @Sendable (InstallProgress) -> Void
  ) async throws -> URL {
    switch package.form {
    case .file(let path):
      return staging.appending(path: path)
    case .coreML(let path):
      progress(.compiling)
      return try await compile(staging.appending(path: path))
    case .coreMLArchive(let path):
      progress(.compiling)
      guard let unpacker else {
        throw ModelInstallError.unpackFailed("no archive unpacker is configured")
      }
      let unpacked = staging.appending(path: "unpacked", directoryHint: .isDirectory)
      do {
        try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
        try unpacker.unpack(staging.appending(path: path), into: unpacked)
      } catch  where Self.isDiskFull(error) {
        throw ModelInstallError.diskFull
      } catch {
        throw ModelInstallError.unpackFailed(error.localizedDescription)
      }
      try Task.checkCancellation()
      guard let model = Self.findCoreMLModel(in: unpacked) else {
        throw ModelInstallError.noModelInArchive
      }
      return try await compile(model)
    }
  }

  private func compile(_ model: URL) async throws -> URL {
    let compiled: URL
    do {
      compiled = try await compiler.compile(model)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw ModelInstallError.compileFailed(error.localizedDescription)
    }
    // The compiler may finish its work regardless of a cancel that came in meanwhile, and a
    // cancel during compiling must not install.
    do {
      try Task.checkCancellation()
    } catch {
      try? FileManager.default.removeItem(at: compiled)
      throw error
    }
    return compiled
  }

  private func fetch(
    _ file: ModelFile, of package: ModelPackage,
    progress: @escaping @Sendable (Int64) -> Void
  ) async throws -> URL {
    do {
      return try await fetcher.fetch(package.url(for: file), progress: progress)
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as URLError where error.code == .cancelled {
      throw CancellationError()
    } catch let error as HTTPStatusError where error.status == 404 {
      throw ModelInstallError.fileMismatch(path: file.path, repo: package.repository)
    } catch let error as HTTPStatusError {
      throw ModelInstallError.httpStatus(error.status)
    } catch let error as ModelInstallError {
      throw error
    } catch  where Self.isDiskFull(error) {
      throw ModelInstallError.diskFull
    } catch {
      throw ModelInstallError.network(error.localizedDescription)
    }
  }

  static func verify(_ url: URL, against file: ModelFile, repo: String) throws {
    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
    guard size == file.bytes, try FileDigest.sha256(of: url) == file.sha256.lowercased() else {
      throw ModelInstallError.fileMismatch(path: file.path, repo: repo)
    }
  }

  /// The first `.mlpackage` or `.mlmodel` under `folder`, whatever the archive's layout.
  static func findCoreMLModel(in folder: URL) -> URL? {
    guard
      let walker = FileManager.default.enumerator(
        at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
    else { return nil }
    for case let url as URL in walker {
      let ext = url.pathExtension.lowercased()
      if ext == "mlpackage" || ext == "mlmodel" { return url }
    }
    return nil
  }

  private static func mappingDiskFull(_ body: () throws -> Void) throws {
    do { try body() } catch  where isDiskFull(error) { throw ModelInstallError.diskFull }
  }

  /// A full disk arrives directly as `CocoaError.fileWriteOutOfSpace` or POSIX `ENOSPC`, or,
  /// from `URLSessionFetcher`, as a `URLError` (e.g. `.cannotWriteToFile`) whose real cause is
  /// nested under `NSUnderlyingErrorKey`. Walks that chain, bounded so a cyclic or pathological
  /// `userInfo` cannot loop forever.
  static func isDiskFull(_ error: any Error) -> Bool {
    var current: any Error = error
    for _ in 0..<8 {
      if let cocoa = current as? CocoaError, cocoa.code == .fileWriteOutOfSpace { return true }
      let ns = current as NSError
      if ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOSPC) { return true }
      guard let underlying = ns.userInfo[NSUnderlyingErrorKey] as? any Error else { return false }
      current = underlying
    }
    return false
  }

  private static func removeEverything(in folder: URL, except keep: URL) {
    let files = FileManager.default
    let children = (try? files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))
    for child in children ?? [] where child.lastPathComponent != keep.lastPathComponent {
      try? files.removeItem(at: child)
    }
  }
}

/// Lets a byte count through every half percent of the download, not on every
/// `didWriteData`: a session reports every few kilobytes, and each report hops to the main
/// actor and redraws whatever reads the install state, thousands of times for a large model.
final class ProgressGate: Sendable {
  private let step: Int64
  private let last = Mutex<Int64>(0)

  init(total: Int64) {
    step = max(total / 200, 1)
  }

  func admit(_ received: Int64) -> Bool {
    last.withLock { last in
      guard received - last >= step else { return false }
      last = received
      return true
    }
  }

  /// Called at each file's end, which is always reported.
  func reset(to received: Int64) {
    last.withLock { $0 = received }
  }
}

/// SHA-256 of a file, read in 4 MB chunks so a several-hundred-megabyte weight file is never
/// in memory whole.
public enum FileDigest {
  public static func sha256(of url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
      hasher.update(data: chunk)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }
}
