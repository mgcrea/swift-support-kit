import CryptoKit
import Foundation

@testable import SupportKitModels

/// A scratch folder per test, removed when the test's value goes away.
///
/// `@unchecked Sendable`: only ever holds an immutable `URL`, but conforming keeps the test
/// struct's `self` a Sendable value so `cancellingLeavesNoStaging` can capture it into a `Task`
/// and still read `locations` afterwards without the compiler flagging a data race.
final class TempDir: @unchecked Sendable {
  let url: URL
  init() {
    url = FileManager.default.temporaryDirectory
      .appending(path: "SupportKitModelsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }
  deinit { try? FileManager.default.removeItem(at: url) }
}

func sha256Hex(_ data: Data) -> String {
  SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

/// A tiny three-file Hugging Face "package", a zipped model and a weights file, and the
/// packages that pin them.
enum Fixture {
  static let manifest = Data("{\"manifest\":1}".utf8)
  static let model = Data(repeating: 7, count: 2048)
  static let weights = Data((0..<4096).map { UInt8($0 % 251) })
  /// What `FakeUnpacker` accepts as an archive.
  static let archive = Data("fake-archive".utf8)

  static func package(id: String = "fake", revision: String = String(repeating: "a", count: 40))
    -> ModelPackage
  {
    let pkg = "Fake.mlpackage"
    func file(_ path: String, _ data: Data) -> ModelFile {
      ModelFile(path: "\(pkg)/\(path)", bytes: Int64(data.count), sha256: sha256Hex(data))
    }
    return .huggingFace(
      id: id,
      HuggingFaceSource(
        repo: "test/\(id)", revision: revision, packagePath: pkg,
        files: [
          file("Manifest.json", manifest), file("Data/model.mlmodel", model),
          file("Data/weights/weight.bin", weights),
        ]))
  }

  /// A single zip at a plain URL, compiled to a fixed name.
  static func archived(id: String = "zipped", data: Data = archive) -> ModelPackage {
    ModelPackage(
      id: id,
      origin: .url(
        URL(string: "https://models.example/\(id)/v1/model.mlpackage.zip")!,
        file: ModelFile(
          path: "download.zip", bytes: Int64(data.count), sha256: sha256Hex(data))),
      form: .coreMLArchive(path: "download.zip"), artifactName: "model.mlmodelc")
  }

  /// Weights kept as downloaded, like MLX's.
  static func weightsFile(id: String = "mlx") -> ModelPackage {
    ModelPackage(
      id: id,
      origin: .url(
        URL(string: "https://models.example/\(id)/v1/weights.safetensors")!,
        file: ModelFile(
          path: "weights.safetensors", bytes: Int64(weights.count), sha256: sha256Hex(weights))),
      form: .file(path: "weights.safetensors"), artifactName: "weights.safetensors")
  }
}

/// Serves bytes by URL path suffix. Behaviour per suffix: normal data, an error, or hanging
/// until cancelled.
final class FakeFetcher: FileFetcher, @unchecked Sendable {
  enum Response {
    case data(Data)
    case error(any Error)
    case hang
  }
  private let lock = NSLock()
  private var responses: [String: Response]
  private(set) var requested: [URL] = []
  /// How many progress reports each file makes on its way in.
  var reportsPerFile = 2

  init(_ responses: [String: Response]) { self.responses = responses }

  /// Every fixture file, served correctly.
  static func serving(weights: Data = Fixture.weights) -> FakeFetcher {
    FakeFetcher([
      "Manifest.json": .data(Fixture.manifest), "model.mlmodel": .data(Fixture.model),
      "weight.bin": .data(weights), "model.mlpackage.zip": .data(Fixture.archive),
      "weights.safetensors": .data(weights),
    ])
  }

  func set(_ suffix: String, _ response: Response) {
    lock.withLock { responses[suffix] = response }
  }

  func fetch(_ url: URL, progress: @escaping @Sendable (Int64) -> Void) async throws -> URL {
    let (response, reports) = lock.withLock {
      requested.append(url)
      return (responses.first { url.path().hasSuffix($0.key) }?.value, reportsPerFile)
    }
    switch response {
    case .data(let data)?:
      for report in 1...reports { progress(Int64(data.count * report / reports)) }
      let out = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
      try data.write(to: out)
      return out
    case .error(let error)?:
      throw error
    case .hang?:
      while true {
        try Task.checkCancellation()
        try await Task.sleep(for: .milliseconds(5))
      }
    case nil:
      throw HTTPStatusError(status: 404)
    }
  }
}

/// Stands in for `MLModel.compileModel`: records the package it was given and returns a
/// folder named like a compiled model.
final class FakeCompiler: ModelCompiler, @unchecked Sendable {
  var failure: (any Error)?
  /// Cancels the task it runs in, then compiles anyway: like `MLModel.compileModel`, which
  /// finishes its work whether or not the caller has since been cancelled.
  var cancelsItsTask = false
  private(set) var compiledPackages: [URL] = []

  func compile(_ package: URL) async throws -> URL {
    if let failure { throw failure }
    if cancelsItsTask { withUnsafeCurrentTask { $0?.cancel() } }
    compiledPackages.append(package)
    let out = FileManager.default.temporaryDirectory
      .appending(path: "\(UUID().uuidString).mlmodelc", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    try Data("compiled".utf8).write(to: out.appending(path: "marker"))
    return out
  }
}

/// "Unpacks" `Fixture.archive` into a nested `.mlpackage`, the way a real zip holds one, or
/// into a folder with no model at all.
struct FakeUnpacker: ArchiveUnpacker {
  var holdsAModel = true

  func unpack(_ archive: URL, into destination: URL) throws {
    guard try Data(contentsOf: archive) == Fixture.archive else {
      throw CocoaError(.fileReadCorruptFile)
    }
    let inner =
      holdsAModel
      ? destination.appending(path: "IsNet/IsNet.mlpackage", directoryHint: .isDirectory)
      : destination.appending(path: "README", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
    try Fixture.manifest.write(to: inner.appending(path: "Manifest.json"))
  }
}

/// Collects progress updates from any thread.
final class Updates: @unchecked Sendable {
  private let lock = NSLock()
  private var items: [InstallProgress] = []
  func append(_ update: InstallProgress) { lock.withLock { items.append(update) } }
  var all: [InstallProgress] { lock.withLock { items } }
}
