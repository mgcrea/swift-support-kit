import Foundation

/// One file of a downloadable model, as the app's registry pins it.
public struct ModelFile: Hashable, Sendable {
  /// Inside the repository at the pinned revision, e.g. `Foo.mlpackage/Manifest.json`, and
  /// the same path in the staging folder.
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

/// Files in a Hugging Face repository, pinned to a commit. A Core ML package is a folder, so
/// it is downloaded file by file and rebuilt in the staging folder under the same paths.
public struct HuggingFaceSource: Hashable, Sendable {
  public let repo: String
  /// A full 40-hex commit, never a branch: a branch can move under a shipped app.
  public let revision: String
  public let files: [ModelFile]

  public init(repo: String, revision: String, files: [ModelFile]) {
    self.repo = repo
    self.revision = revision
    self.files = files
  }

  public func url(for file: ModelFile) -> URL {
    URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(file.path)")!
  }
}

/// What `ModelInstaller` needs to put one model on disk: which pinned files to fetch, what to
/// do with them once they are verified, and the name the finished model takes in its folder.
///
/// The app's registry stays the app's: it knows which pipeline step or which Pro tier a model
/// belongs to. It hands the installer one of these per downloadable entry.
public struct ModelPackage: Identifiable, Hashable, Sendable {
  /// What the verified files become. Every `path` is relative to the staging folder, which
  /// mirrors the repository.
  public enum Form: Hashable, Sendable {
    /// Compile `path` with the installer's `ModelCompiler`: an `.mlpackage` folder rebuilt
    /// from the files, or a single `.mlmodel`.
    case coreML(path: String)
    /// Keep the file at `path` as it is: weights a runtime such as MLX loads directly.
    case file(path: String)
  }

  /// Stable: it names the model's folder on disk.
  public let id: String
  public let source: HuggingFaceSource
  public let form: Form
  /// The finished model's name inside its folder. A new name means a new version: whatever
  /// else sits in the folder with the same extension is the previous one, still usable
  /// (`outdated`) until the new one is in place.
  public let artifactName: String

  public init(id: String, source: HuggingFaceSource, form: Form, artifactName: String) {
    self.id = id
    self.source = source
    self.form = form
    self.artifactName = artifactName
  }

  /// A Core ML package compiled to `<revision>.mlmodelc`, so pinning a newer revision leaves
  /// the older one usable until the update lands.
  public static func huggingFace(id: String, _ source: HuggingFaceSource, packagePath: String)
    -> ModelPackage
  {
    ModelPackage(
      id: id, source: source, form: .coreML(path: packagePath),
      artifactName: "\(source.revision).mlmodelc")
  }

  public var files: [ModelFile] { source.files }

  /// What a download costs, for the size shown before it starts and the progress bar.
  public var totalBytes: Int64 { files.reduce(0) { $0 + $1.bytes } }

  public func url(for file: ModelFile) -> URL { source.url(for: file) }
}
