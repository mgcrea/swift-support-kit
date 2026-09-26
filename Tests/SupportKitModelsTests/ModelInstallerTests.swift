import Foundation
import Testing

@testable import SupportKitModels

@Suite("Model installer")
struct ModelInstallerTests {
  let temp = TempDir()
  var locations: ModelLocations { ModelLocations(root: temp.url) }

  private func installer(
    _ fetcher: FakeFetcher, _ compiler: FakeCompiler = FakeCompiler(),
    unpacker: (any ArchiveUnpacker)? = FakeUnpacker()
  ) -> ModelInstaller {
    ModelInstaller(locations: locations, fetcher: fetcher, compiler: compiler, unpacker: unpacker)
  }

  private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path()) }

  // MARK: - Hugging Face packages

  @Test func installsEveryFileThenCompilesThePackage() async throws {
    let compiler = FakeCompiler()
    let package = Fixture.package()
    let updates = Updates()
    let url = try await installer(.serving(), compiler).install(package) { updates.append($0) }

    #expect(url == locations.compiled(for: "fake", revision: String(repeating: "a", count: 40)))
    #expect(url == locations.artifact(of: package))
    #expect(exists(url.appending(path: "marker")))
    #expect(!exists(locations.staging(for: "fake")))
    let compiled = try #require(compiler.compiledPackages.first)
    #expect(compiled.lastPathComponent == "Fake.mlpackage")
    #expect(updates.all.last == .compiling)
    #expect(updates.all.contains(.verifying))
    #expect(
      updates.all.contains(.downloading(received: package.totalBytes, total: package.totalBytes)))
  }

  @Test func aWrongSizeFailsNamingTheFile() async {
    let fetcher = FakeFetcher.serving(weights: Data(repeating: 1, count: 10))
    await #expect(
      throws: ModelInstallError.fileMismatch(
        path: "Fake.mlpackage/Data/weights/weight.bin", repo: "test/fake")
    ) {
      try await installer(fetcher).install(Fixture.package()) { _ in }
    }
    #expect(!exists(locations.staging(for: "fake")))
  }

  @Test func aWrongHashOfTheRightSizeFails() async {
    var tampered = Fixture.weights
    tampered[0] ^= 0xFF
    await #expect(throws: ModelInstallError.self) {
      try await installer(.serving(weights: tampered)).install(Fixture.package()) { _ in }
    }
    #expect(!exists(locations.staging(for: "fake")))
  }

  /// A pinned commit that no longer exists answers 404.
  @Test func notFoundIsAMismatchNamingTheRepo() async {
    let fetcher = FakeFetcher.serving()
    fetcher.set("model.mlmodel", .error(HTTPStatusError(status: 404)))
    await #expect(
      throws: ModelInstallError.fileMismatch(
        path: "Fake.mlpackage/Data/model.mlmodel", repo: "test/fake")
    ) {
      try await installer(fetcher).install(Fixture.package()) { _ in }
    }
  }

  @Test func anotherStatusIsReportedAsIs() async {
    let fetcher = FakeFetcher.serving()
    fetcher.set("model.mlmodel", .error(HTTPStatusError(status: 403)))
    await #expect(throws: ModelInstallError.httpStatus(403)) {
      try await installer(fetcher).install(Fixture.package()) { _ in }
    }
  }

  @Test func otherFailuresAreNetworkErrors() async {
    let fetcher = FakeFetcher.serving()
    fetcher.set("Manifest.json", .error(URLError(.notConnectedToInternet)))
    let error = await #expect(throws: ModelInstallError.self) {
      try await installer(fetcher).install(Fixture.package()) { _ in }
    }
    guard case .network? = error else {
      Issue.record("expected a network error, got \(String(describing: error))")
      return
    }
  }

  /// The disk fills during a download.
  @Test func aFullDiskSaysSoAndLeavesNoStaging() async {
    let fetcher = FakeFetcher.serving()
    fetcher.set("weight.bin", .error(CocoaError(.fileWriteOutOfSpace)))
    await #expect(throws: ModelInstallError.diskFull) {
      try await installer(fetcher).install(Fixture.package()) { _ in }
    }
    #expect(!exists(locations.staging(for: "fake")))
  }

  /// `URLSessionFetcher` reports a full disk as a `URLError` whose real cause is nested under
  /// `NSUnderlyingErrorKey`, not as a bare `CocoaError` or POSIX error.
  @Test func aFullDiskBehindAURLErrorSaysSoAndLeavesNoStaging() async {
    let fetcher = FakeFetcher.serving()
    let cause = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
    fetcher.set(
      "weight.bin",
      .error(URLError(.cannotWriteToFile, userInfo: [NSUnderlyingErrorKey: cause])))
    await #expect(throws: ModelInstallError.diskFull) {
      try await installer(fetcher).install(Fixture.package()) { _ in }
    }
    #expect(!exists(locations.staging(for: "fake")))
  }

  @Test func cancellingLeavesNoStaging() async {
    let fetcher = FakeFetcher.serving()
    fetcher.set("weight.bin", .hang)
    let task = Task { try await installer(fetcher).install(Fixture.package()) { _ in } }
    try? await Task.sleep(for: .milliseconds(50))
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(!exists(locations.staging(for: "fake")))
  }

  @Test func aCompileFailureIsReported() async {
    let compiler = FakeCompiler()
    compiler.failure = CocoaError(.fileReadCorruptFile)
    let error = await #expect(throws: ModelInstallError.self) {
      try await installer(.serving(), compiler).install(Fixture.package()) { _ in }
    }
    guard case .compileFailed? = error else {
      Issue.record("expected compileFailed, got \(String(describing: error))")
      return
    }
    #expect(!exists(locations.staging(for: "fake")))
  }

  /// Cancelling while the model is being prepared must not install it.
  @Test func cancellingDuringCompileInstallsNothing() async {
    let compiler = FakeCompiler()
    compiler.cancelsItsTask = true
    let package = Fixture.package()
    await #expect(throws: CancellationError.self) {
      try await installer(.serving(), compiler).install(package) { _ in }
    }
    #expect(!exists(locations.artifact(of: package)))
    #expect(!exists(locations.staging(for: "fake")))
  }

  @Test func aCompilerCancellationIsACancellation() async {
    let compiler = FakeCompiler()
    compiler.failure = CancellationError()
    await #expect(throws: CancellationError.self) {
      try await installer(.serving(), compiler).install(Fixture.package()) { _ in }
    }
    #expect(!exists(locations.staging(for: "fake")))
  }

  /// Models are re-downloadable, so they stay out of the user's backups.
  @Test func theModelsFolderIsExcludedFromBackup() async throws {
    _ = try await installer(.serving()).install(Fixture.package()) { _ in }
    let values = try locations.root.resourceValues(forKeys: [.isExcludedFromBackupKey])
    #expect(values.isExcludedFromBackup == true)
  }

  @Test func aNewRevisionReplacesTheOldOne() async throws {
    let old = locations.compiled(for: "fake", revision: String(repeating: "b", count: 40))
    try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
    let url = try await installer(.serving()).install(Fixture.package()) { _ in }
    #expect(exists(url))
    #expect(!exists(old))
  }

  /// A session reports every few kilobytes; the store must not hop to the main actor for each.
  @Test func progressIsReportedInSteps() async throws {
    let fetcher = FakeFetcher.serving()
    fetcher.reportsPerFile = 5_000
    let updates = Updates()
    _ = try await installer(fetcher).install(Fixture.package()) { updates.append($0) }
    let downloading = updates.all.filter {
      if case .downloading = $0 { true } else { false }
    }
    #expect(downloading.count <= 210)
    #expect(downloading.count > 10)
  }

  // MARK: - Archives

  @Test func anArchiveIsUnpackedAndTheModelInsideCompiled() async throws {
    let compiler = FakeCompiler()
    let package = Fixture.archived()
    let updates = Updates()
    let url = try await installer(.serving(), compiler).install(package) { updates.append($0) }

    #expect(url == locations.artifact(of: package))
    #expect(url.path(percentEncoded: false).hasSuffix("/zipped/model.mlmodelc/"))
    #expect(exists(url.appending(path: "marker")))
    #expect(!exists(locations.staging(for: "zipped")))
    #expect(compiler.compiledPackages.first?.lastPathComponent == "IsNet.mlpackage")
    #expect(updates.all.last == .compiling)
  }

  @Test func anArchiveWithNoModelSaysSo() async {
    await #expect(throws: ModelInstallError.noModelInArchive) {
      try await installer(.serving(), unpacker: FakeUnpacker(holdsAModel: false))
        .install(Fixture.archived()) { _ in }
    }
    #expect(!exists(locations.staging(for: "zipped")))
  }

  @Test func anArchiveNeedsAnUnpacker() async {
    let error = await #expect(throws: ModelInstallError.self) {
      try await installer(.serving(), unpacker: nil).install(Fixture.archived()) { _ in }
    }
    guard case .unpackFailed? = error else {
      Issue.record("expected unpackFailed, got \(String(describing: error))")
      return
    }
  }

  /// An archive checked against its pinned hash before anything reads it.
  @Test func aTamperedArchiveIsRefusedBeforeUnpacking() async {
    let fetcher = FakeFetcher.serving()
    fetcher.set("model.mlpackage.zip", .data(Data("fake-archivf".utf8)))
    await #expect(
      throws: ModelInstallError.fileMismatch(path: "download.zip", repo: "models.example")
    ) {
      try await installer(fetcher).install(Fixture.archived()) { _ in }
    }
  }

  // MARK: - Plain files

  @Test func aFileIsKeptAsDownloadedAndNeverCompiled() async throws {
    let compiler = FakeCompiler()
    let updates = Updates()
    let url = try await installer(.serving(), compiler).install(Fixture.weightsFile()) {
      updates.append($0)
    }
    #expect(url == locations.folder(for: "mlx").appending(path: "weights.safetensors"))
    #expect(try Data(contentsOf: url) == Fixture.weights)
    #expect(compiler.compiledPackages.isEmpty)
    #expect(!updates.all.contains(.compiling))
    // Verifying is the last thing it does, with no byte count after it.
    #expect(updates.all.last == .verifying)
    #expect(!exists(locations.staging(for: "mlx")))
  }

  /// A leftover from anything but the finished model goes once the install lands: an older
  /// app's `download.tmp`, say.
  @Test func anInstallClearsWhateverElseIsInTheFolder() async throws {
    let folder = locations.folder(for: "mlx")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data(count: 10).write(to: folder.appending(path: "download.tmp"))
    let url = try await installer(.serving()).install(Fixture.weightsFile()) { _ in }
    let left = try FileManager.default.contentsOfDirectory(atPath: folder.path())
    #expect(left == [url.lastPathComponent])
  }

  @Test func diskUsageCountsEveryFile() throws {
    let folder = locations.folder(for: "x")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data(count: 1000).write(to: folder.appending(path: "a"))
    try Data(count: 24).write(to: folder.appending(path: "b"))
    #expect(locations.diskUsage() == 1024)
  }
}
