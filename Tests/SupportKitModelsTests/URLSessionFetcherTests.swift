import Foundation
import Testing

@testable import SupportKitModels

/// `URLSessionFetcher` against a `URLProtocol` stub, so the real delegate plumbing runs
/// without the network. The URL's path picks the stub's behaviour.
@Suite("URLSession fetcher")
struct URLSessionFetcherTests {
  private let fetcher: URLSessionFetcher = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubProtocol.self]
    return URLSessionFetcher(configuration: configuration)
  }()

  @Test func downloadsEveryChunkAndReportsProgress() async throws {
    let received = Received()
    let url = try await fetcher.fetch(StubProtocol.url(.chunks)) { received.append($0) }
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(try Data(contentsOf: url) == StubProtocol.body)
    #expect(!received.all.isEmpty)
    #expect(received.all.max() == Int64(StubProtocol.body.count))
  }

  @Test func notFoundThrowsTheStatus() async {
    await #expect(throws: HTTPStatusError(status: 404)) {
      _ = try await fetcher.fetch(StubProtocol.url(.notFound)) { _ in }
    }
  }

  /// The race below, made deterministic: the task's completion reaches the delegate before
  /// the awaiting side attaches its continuation. The result must wait for it, not be lost.
  @Test func aCompletionBeforeTheContinuationIsAttachedIsKept() async throws {
    let delegate = DownloadDelegate(progress: { _ in })
    let session = URLSession(configuration: .ephemeral)
    defer { session.invalidateAndCancel() }
    let download = session.downloadTask(with: StubProtocol.url(.hang))
    delegate.urlSession(session, task: download, didCompleteWithError: URLError(.cancelled))

    let outcome = Outcome()
    Task {
      do {
        _ = try await withCheckedThrowingContinuation { delegate.attach($0) }
        outcome.set("returned")
      } catch let error as URLError where error.code == .cancelled {
        outcome.set("cancelled")
      } catch {
        outcome.set("threw \(error)")
      }
    }
    let deadline = ContinuousClock.now + .seconds(2)
    while outcome.value == nil && ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(1))
    }
    #expect(outcome.value == "cancelled")
  }

  /// A cancellation that lands before, during or after the download task starts must still
  /// end the fetch: the task's completion can reach the delegate before the awaiting side has
  /// handed over its continuation, and that result must not be dropped.
  @Test(arguments: [false, true])
  func cancellingAlwaysEndsTheFetch(afterADelay: Bool) async throws {
    for attempt in 0..<200 {
      let outcome = Outcome()
      let fetcher = self.fetcher
      let task = Task {
        do {
          let url = try await fetcher.fetch(StubProtocol.url(.hang)) { _ in }
          try? FileManager.default.removeItem(at: url)
          outcome.set("returned")
        } catch let error as URLError where error.code == .cancelled {
          outcome.set("cancelled")
        } catch is CancellationError {
          outcome.set("cancelled")
        } catch {
          outcome.set("threw \(error)")
        }
      }
      if afterADelay { try await Task.sleep(for: .microseconds(Int.random(in: 0...3_000))) }
      task.cancel()
      // Polled, not awaited: a fetch that never returns would otherwise hang the suite.
      let deadline = ContinuousClock.now + .seconds(5)
      while outcome.value == nil && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(1))
      }
      guard let value = outcome.value else {
        Issue.record("attempt \(attempt): the fetch never returned after cancellation")
        return
      }
      #expect(value == "cancelled", "attempt \(attempt)")
    }
  }
}

/// Serves `body` in several chunks, never answers, or answers 404.
final class StubProtocol: URLProtocol, @unchecked Sendable {
  enum Behaviour: String {
    case chunks, hang, notFound
  }

  static let body = Data((0..<48_000).map { UInt8($0 % 253) })

  static func url(_ behaviour: Behaviour) -> URL {
    URL(string: "https://stub.invalid/\(behaviour.rawValue)")!
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url, let client else { return }
    switch Behaviour(rawValue: url.lastPathComponent) {
    case .chunks:
      respond(url, status: 200, length: Self.body.count)
      let size = Self.body.count / 4
      for start in stride(from: 0, to: Self.body.count, by: size) {
        client.urlProtocol(self, didLoad: Self.body[start..<min(start + size, Self.body.count)])
      }
      client.urlProtocolDidFinishLoading(self)
    case .notFound:
      let page = Data("Entry not found".utf8)
      respond(url, status: 404, length: page.count)
      client.urlProtocol(self, didLoad: page)
      client.urlProtocolDidFinishLoading(self)
    case .hang, nil:
      break  // until the task is cancelled
    }
  }

  override func stopLoading() {}

  private func respond(_ url: URL, status: Int, length: Int) {
    let response = HTTPURLResponse(
      url: url, statusCode: status, httpVersion: "HTTP/1.1",
      headerFields: ["Content-Length": "\(length)"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
  }
}

/// Byte counts reported from any thread.
private final class Received: @unchecked Sendable {
  private let lock = NSLock()
  private var items: [Int64] = []
  func append(_ value: Int64) { lock.withLock { items.append(value) } }
  var all: [Int64] { lock.withLock { items } }
}

/// How one fetch ended, set once from the fetching task.
private final class Outcome: @unchecked Sendable {
  private let lock = NSLock()
  private var result: String?
  func set(_ value: String) { lock.withLock { result = value } }
  var value: String? { lock.withLock { result } }
}
