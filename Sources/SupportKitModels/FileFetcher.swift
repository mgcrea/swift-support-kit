import Foundation

/// Downloads one file. The installer depends on this rather than on `URLSession`, so tests
/// serve files from memory and never touch the network.
public protocol FileFetcher: Sendable {
  /// Downloads `url` to a temporary file the caller then owns, reporting bytes received.
  func fetch(_ url: URL, progress: @escaping @Sendable (Int64) -> Void) async throws -> URL
}

/// A response that was not 2xx. Hugging Face answers 404 for a file missing at a revision.
public struct HTTPStatusError: Error, Equatable {
  public let status: Int
}

/// Downloads with a session-level delegate, not a task-level one: only a session delegate
/// actually receives `didWriteData` as bytes arrive. `session.download(from:delegate:)` takes
/// a *task* delegate, and in practice that gets none of them for a real network download,
/// however large the file — confirmed by experiment (0 calls for a 20 MB file through that
/// API, versus 174 for the same file through a session-level delegate on a `downloadTask`).
/// Reporting nothing until the whole file lands leaves a progress bar frozen for the length
/// of a several-hundred-megabyte download.
public struct URLSessionFetcher: FileFetcher {
  private let configuration: URLSessionConfiguration

  public init(configuration: URLSessionConfiguration = .default) {
    self.configuration = configuration
  }

  public func fetch(_ url: URL, progress: @escaping @Sendable (Int64) -> Void) async throws
    -> URL
  {
    let delegate = DownloadDelegate(progress: progress)
    let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    defer { session.finishTasksAndInvalidate() }
    let task = session.downloadTask(with: url)
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        delegate.attach(continuation)
        task.resume()
      }
    } onCancel: {
      task.cancel()
    }
  }
}

/// Bridges one `URLSessionDownloadTask` to structured concurrency. A session (not a task)
/// delegate, created fresh per fetch so each download's progress reaches only its own caller.
/// Internal rather than private so a test can deliver a completion before `attach`.
final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  private let progress: @Sendable (Int64) -> Void
  private let lock = NSLock()
  private var continuation: CheckedContinuation<URL, any Error>?
  /// A result that arrived before `attach`, held until the continuation shows up.
  private var pending: Result<URL, any Error>?
  private var finished = false

  init(progress: @escaping @Sendable (Int64) -> Void) {
    self.progress = progress
  }

  /// Called before `task.resume()`, but a cancelled task can still complete first: if the
  /// fetch was cancelled on entry, `onCancel` runs `task.cancel()` before this, and the
  /// session may report that on its own queue at once. A result already in hand is delivered
  /// here instead of waiting for a callback that has come and gone.
  func attach(_ continuation: CheckedContinuation<URL, any Error>) {
    let ready: Result<URL, any Error>? = lock.withLock {
      if let pending {
        self.pending = nil
        return pending
      }
      self.continuation = continuation
      return nil
    }
    if let ready { continuation.resume(with: ready) }
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
  ) {
    progress(totalBytesWritten)
  }

  /// Runs synchronously, before this delegate call returns: `location` is a file in
  /// `URLSession`'s own scratch space that it deletes right after, so the move to somewhere
  /// this process owns has to happen here, not after hopping back to the awaiting task.
  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode)
    {
      try? FileManager.default.removeItem(at: location)
      finish(.failure(HTTPStatusError(status: http.statusCode)))
      return
    }
    let kept = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    do {
      try FileManager.default.moveItem(at: location, to: kept)
      finish(.success(kept))
    } catch {
      finish(.failure(error))
    }
  }

  /// Always called last, success or failure (including cancellation, as a `URLError` whose
  /// `.code == .cancelled` the installer already maps to `CancellationError`). On success
  /// `didFinishDownloadingTo` already resolved the result and `finish` ignores this one; the
  /// fallback error only lands if a task somehow completed cleanly without a file, so the
  /// fetch still ends.
  func urlSession(
    _ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?
  ) {
    finish(.failure(error ?? URLError(.zeroByteResource)))
  }

  /// Delivers the first result exactly once: to the attached continuation, or into `pending`
  /// for `attach` to pick up. Any later result (a completion after `didFinishDownloadingTo`
  /// already resolved) is dropped.
  private func finish(_ result: Result<URL, any Error>) {
    let continuation: CheckedContinuation<URL, any Error>? = lock.withLock {
      guard !finished else { return nil }
      finished = true
      guard let attached = self.continuation else {
        pending = result
        return nil
      }
      self.continuation = nil
      return attached
    }
    continuation?.resume(with: result)
  }
}
