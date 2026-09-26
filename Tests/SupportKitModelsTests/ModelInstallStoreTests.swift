import Foundation
import Testing

@testable import SupportKitModels

@Suite("Model install store")
@MainActor
struct ModelInstallStoreTests {
  let temp = TempDir()
  let a = Fixture.package(id: "a")
  let b = Fixture.package(id: "b")
  let weights = Fixture.weightsFile()

  var locations: ModelLocations { ModelLocations(root: temp.url) }

  private func store(
    fetcher: FakeFetcher = .serving(), compiler: FakeCompiler = FakeCompiler(),
    describe: (@Sendable (any Error) -> String)? = nil
  ) -> ModelInstallStore {
    let installer = ModelInstaller(locations: locations, fetcher: fetcher, compiler: compiler)
    if let describe {
      return ModelInstallStore(installer: installer, packages: [a, b, weights], describe: describe)
    }
    return ModelInstallStore(installer: installer, packages: [a, b, weights])
  }

  private func fakeInstalled(_ package: ModelPackage, revision: String? = nil) throws -> URL {
    let url =
      revision.map { locations.compiled(for: package.id, revision: $0) }
      ?? locations.artifact(of: package)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test func launchReadsWhatIsOnDisk() throws {
    let ready = try fakeInstalled(a)
    let old = try fakeInstalled(b, revision: String(repeating: "c", count: 40))
    let s = store()
    #expect(s.state(of: "a") == .ready(ready))
    #expect(s.state(of: "b") == .outdated(old))
    #expect(s.installedURL(of: "b") == old)
    #expect(s.state(of: "mlx") == .notInstalled)
    #expect(s.state(of: "unknown") == .notInstalled)
  }

  /// The app quit mid-download.
  @Test func launchSweepsAnAbandonedDownload() throws {
    let staging = locations.staging(for: "a")
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    let s = store()
    #expect(s.state(of: "a") == .notInstalled)
    #expect(!FileManager.default.fileExists(atPath: staging.path()))
  }

  /// A folder installed before the store set the flag is excluded at launch too.
  @Test func launchExcludesTheModelsFolderFromBackup() throws {
    _ = try fakeInstalled(a)
    _ = store()
    let values = try locations.root.resourceValues(forKeys: [.isExcludedFromBackupKey])
    #expect(values.isExcludedFromBackup == true)
  }

  @Test func installEndsReadyAndReportsIt() async {
    let s = store()
    let finished = Finished()
    await s.install(weights) { finished.result = $0 }.value
    let url = locations.artifact(of: weights)
    #expect(s.state(of: "mlx") == .ready(url))
    #expect(s.installedURL(of: "mlx") == url)
    #expect(finished.url == url)
  }

  @Test func installingAReadyModelDoesNothing() async throws {
    _ = try fakeInstalled(a)
    let fetcher = FakeFetcher.serving()
    let s = store(fetcher: fetcher)
    await s.install(a).value
    #expect(fetcher.requested.isEmpty)
  }

  @Test func installingTwiceRunsOneDownload() async {
    let fetcher = FakeFetcher.serving()
    let s = store(fetcher: fetcher)
    let first = s.install(a)
    let second = s.install(a)
    await first.value
    await second.value
    #expect(fetcher.requested.count == 3)
  }

  @Test func aFailureShowsItsMessage() async {
    let fetcher = FakeFetcher.serving()
    fetcher.set("Manifest.json", .error(CocoaError(.fileWriteOutOfSpace)))
    let s = store(fetcher: fetcher)
    await s.install(a).value
    #expect(s.state(of: "a") == .failed(ModelInstallError.diskFull.localizedDescription))
    #expect(s.lastError(of: "a") == ModelInstallError.diskFull.localizedDescription)
  }

  @Test func anAppCanWordTheFailure() async {
    let fetcher = FakeFetcher.serving()
    fetcher.set("Manifest.json", .error(CocoaError(.fileWriteOutOfSpace)))
    let s = store(fetcher: fetcher) { error in
      error as? ModelInstallError == .diskFull ? "Disque plein." : "?"
    }
    await s.install(a).value
    #expect(s.state(of: "a") == .failed("Disque plein."))
  }

  @Test func cancellingReturnsToNotInstalled() async throws {
    let fetcher = FakeFetcher.serving()
    fetcher.set("weight.bin", .hang)
    let s = store(fetcher: fetcher)
    let task = s.install(a)
    try await Task.sleep(for: .milliseconds(50))
    s.cancel("a")
    await task.value
    #expect(s.state(of: "a") == .notInstalled)
  }

  /// A cancelled install's late result must not clobber a reinstall that started before it
  /// finished unwinding: uninstall cancels and clears the run, but the task itself keeps
  /// running until its `Task.checkCancellation()` fires, and that can land after a fresh
  /// `install(a)` is already under way.
  @Test func aStaleCancelledInstallDoesNotClobberAReinstall() async throws {
    let fetcher = FakeFetcher.serving()
    fetcher.set("weight.bin", .hang)
    let s = store(fetcher: fetcher)
    let firstFinished = Finished()
    let first = s.install(a) { firstFinished.result = $0 }
    try await Task.sleep(for: .milliseconds(50))
    s.uninstall("a")
    fetcher.set("weight.bin", .data(Fixture.weights))
    let second = s.install(a)
    await first.value
    await second.value
    guard case .ready = s.state(of: "a") else {
      Issue.record("expected ready, got \(String(describing: s.state(of: "a")))")
      return
    }
    // The superseded run is not reported as finished either.
    #expect(firstFinished.result == nil)
  }

  @Test func uninstallDeletesTheFolder() throws {
    _ = try fakeInstalled(a)
    let s = store()
    s.uninstall("a")
    #expect(s.state(of: "a") == .notInstalled)
    #expect(s.installedURL(of: "a") == nil)
    #expect(!FileManager.default.fileExists(atPath: locations.folder(for: "a").path()))
  }

  /// "The old folder stays usable until the new one is ready".
  @Test func anOutdatedModelStaysUsableWhileItUpdates() async throws {
    let old = try fakeInstalled(a, revision: String(repeating: "d", count: 40))
    let fetcher = FakeFetcher.serving()
    fetcher.set("weight.bin", .hang)
    let s = store(fetcher: fetcher)
    let task = s.install(a)
    guard case .downloading = s.state(of: "a") else {
      Issue.record("expected downloading, got \(String(describing: s.state(of: "a")))")
      return
    }
    #expect(s.installedURL(of: "a") == old)
    s.cancel("a")
    await task.value
    #expect(s.state(of: "a") == .outdated(old))
    #expect(s.installedURL(of: "a") == old)
    #expect(s.lastError(of: "a") == nil)
  }

  @Test func aFailedUpdateKeepsTheOldModelAndSaysWhy() async throws {
    let old = try fakeInstalled(a, revision: String(repeating: "d", count: 40))
    let fetcher = FakeFetcher.serving()
    fetcher.set("Manifest.json", .error(CocoaError(.fileWriteOutOfSpace)))
    let s = store(fetcher: fetcher)
    await s.install(a).value
    #expect(s.state(of: "a") == .outdated(old))
    #expect(s.lastError(of: "a") == ModelInstallError.diskFull.localizedDescription)
    #expect(s.installedURL(of: "a") == old)

    fetcher.set("Manifest.json", .data(Fixture.manifest))
    let retry = s.install(a)
    #expect(s.lastError(of: "a") == nil)
    await retry.value
    #expect(s.state(of: "a") == .ready(locations.artifact(of: a)))
    #expect(!FileManager.default.fileExists(atPath: old.path()))
  }

  @Test func aModelWhoseUpdateFailedCanBeRemoved() async throws {
    _ = try fakeInstalled(a, revision: String(repeating: "d", count: 40))
    let fetcher = FakeFetcher.serving()
    fetcher.set("Manifest.json", .error(URLError(.networkConnectionLost)))
    let s = store(fetcher: fetcher)
    await s.install(a).value
    s.uninstall("a")
    #expect(s.state(of: "a") == .notInstalled)
    #expect(s.lastError(of: "a") == nil)
    #expect(s.installedURL(of: "a") == nil)
  }

  @Test func retryingAfterAFailureEndsReady() async {
    let fetcher = FakeFetcher.serving()
    fetcher.set("weight.bin", .error(URLError(.networkConnectionLost)))
    let s = store(fetcher: fetcher)
    await s.install(a).value
    guard case .failed = s.state(of: "a") else {
      Issue.record("expected failed, got \(String(describing: s.state(of: "a")))")
      return
    }
    fetcher.set("weight.bin", .data(Fixture.weights))
    await s.install(a).value
    #expect(s.state(of: "a") == .ready(locations.artifact(of: a)))
    #expect(s.lastError(of: "a") == nil)
  }
}

/// What `onFinish` handed over, set on the main actor.
@MainActor
private final class Finished {
  var result: Result<URL, any Error>?
  var url: URL? { try? result?.get() }
}
