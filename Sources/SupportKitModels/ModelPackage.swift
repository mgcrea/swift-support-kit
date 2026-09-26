import Foundation

/// One file of a downloadable model, as the app's registry pins it.
public struct ModelFile: Hashable, Sendable {
  /// Where the file lands in the staging folder. For a Hugging Face model it is also the path
  /// inside the repository at the pinned revision, e.g. `Foo.mlpackage/Manifest.json`.
  public let path: String
  public let bytes: Int64
  /// 64 lowercase hex characters.
  public let sha256: String

  public init(path: String, bytes: Int64, sha256: String) {
    self.path = path
    self.bytes = bytes
    self.sha256 = sha256
  }
}

/// A Core ML package on Hugging Face, pinned to a commit. A package is a folder, so it is
/// downloaded file by file and rebuilt under `packagePath`.
public struct HuggingFaceSource: Hashable, Sendable {
  public let repo: String
  /// A full 40-hex commit, never a branch: a branch can move under a shipped app.
  public let revision: String
  /// The `.mlpackage` folder inside the repository; every file path starts with it.
  public let packagePath: String
  public let files: [ModelFile]

  public init(repo: String, revision: String, packagePath: String, files: [ModelFile]) {
    self.repo = repo
    self.revision = revision
    self.packagePath = packagePath
    self.files = files
  }

  public func url(for file: ModelFile) -> URL {
    URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(file.path)")!
  }
}

/// What `ModelInstaller` needs to put one model on disk: where its files come from, what to
/// do with them once they are verified, and the name the finished model takes in its folder.
///
/// The app's registry stays the app's: it knows which pipeline step or which Pro tier a model
/// belongs to. It hands the installer one of these per downloadable entry.
public struct ModelPackage: Identifiable, Hashable, Sendable {
  public enum Origin: Hashable, Sendable {
    case huggingFace(HuggingFaceSource)
    /// One file at a plain URL, such as a bucket the app's maintainer hosts. `file.path` is
    /// the name it takes in the staging folder, not anything in the URL.
    case url(URL, file: ModelFile)
  }

  /// What the verified files become. Every `path` is relative to the staging folder.
  public enum Form: Hashable, Sendable {
    /// Compile `path` with the installer's `ModelCompiler`: an `.mlpackage` folder rebuilt
    /// from the files, or a single `.mlmodel`.
    case coreML(path: String)
    /// Unpack the archive at `path` with the installer's `ArchiveUnpacker`, then compile the
    /// first `.mlpackage` or `.mlmodel` inside it. The package depends on no archive library,
    /// so the app brings the unpacker.
    case coreMLArchive(path: String)
    /// Keep the file at `path` as it is: weights a runtime such as MLX loads directly.
    case file(path: String)
  }

  /// Stable: it names the model's folder on disk.
  public let id: String
  public let origin: Origin
  public let form: Form
  /// The finished model's name inside its folder. A new name means a new version: whatever
  /// else sits in the folder with the same extension is the previous one, still usable
  /// (`outdated`) until the new one is in place.
  public let artifactName: String

  public init(id: String, origin: Origin, form: Form, artifactName: String) {
    self.id = id
    self.origin = origin
    self.form = form
    self.artifactName = artifactName
  }

  /// A Hugging Face Core ML package, compiled to `<revision>.mlmodelc`, so pinning a newer
  /// revision leaves the older one usable until the update lands.
  public static func huggingFace(id: String, _ source: HuggingFaceSource) -> ModelPackage {
    ModelPackage(
      id: id, origin: .huggingFace(source), form: .coreML(path: source.packagePath),
      artifactName: "\(source.revision).mlmodelc")
  }

  public var files: [ModelFile] {
    switch origin {
    case .huggingFace(let source): source.files
    case .url(_, let file): [file]
    }
  }

  /// What a download costs, for the size shown before it starts and the progress bar.
  public var totalBytes: Int64 { files.reduce(0) { $0 + $1.bytes } }

  public func url(for file: ModelFile) -> URL {
    switch origin {
    case .huggingFace(let source): source.url(for: file)
    case .url(let url, _): url
    }
  }

  /// Where the files come from, as an error message names it: where a fix starts.
  var repository: String {
    switch origin {
    case .huggingFace(let source): source.repo
    case .url(let url, _): url.host() ?? url.absoluteString
    }
  }
}
