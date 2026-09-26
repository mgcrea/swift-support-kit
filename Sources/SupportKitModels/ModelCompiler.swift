import CoreML
import Foundation

/// Turns a downloaded `.mlpackage` (or `.mlmodel`) into a loadable `.mlmodelc`. A protocol so
/// the installer's tests do not need a real model.
public protocol ModelCompiler: Sendable {
  /// Returns the compiled model in a temporary location the caller then moves.
  func compile(_ package: URL) async throws -> URL
}

public struct CoreMLCompiler: ModelCompiler {
  public init() {}

  public func compile(_ package: URL) async throws -> URL {
    try await MLModel.compileModel(at: package)
  }
}

/// Unpacks a downloaded archive for `ModelPackage.Form.coreMLArchive`. The package links no
/// archive library, so an app that ships zipped models brings its own.
public protocol ArchiveUnpacker: Sendable {
  /// Extracts `archive` into `destination`, a folder that already exists.
  func unpack(_ archive: URL, into destination: URL) throws
}
