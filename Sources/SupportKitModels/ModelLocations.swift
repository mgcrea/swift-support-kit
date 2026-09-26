import Foundation

/// Where models live on disk. One folder per model id; inside it a `staging` folder while a
/// download runs and the finished model (`ModelPackage.artifactName`) once it is ready.
public struct ModelLocations: Sendable {
  public let root: URL

  public init(root: URL) {
    self.root = root
  }

  /// `~/Library/Application Support/<folder>/Models` (inside the sandbox container).
  public static func applicationSupport(_ folder: String) -> ModelLocations {
    ModelLocations(
      root: URL.applicationSupportDirectory.appending(
        path: "\(folder)/Models", directoryHint: .isDirectory))
  }

  /// Creates the root if needed and keeps it out of backups.
  func createRoot() throws {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    excludeFromBackup()
  }

  /// Every model in the root can be downloaded again, so it has no business in Time Machine
  /// or iCloud. Best-effort: failing to set it is no reason to refuse a download, and a root
  /// that does not exist yet has nothing to exclude.
  func excludeFromBackup() {
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    var url = root
    try? url.setResourceValues(values)
  }

  public func folder(for id: String) -> URL {
    root.appending(path: id, directoryHint: .isDirectory)
  }

  public func staging(for id: String) -> URL {
    folder(for: id).appending(path: "staging", directoryHint: .isDirectory)
  }

  /// The finished model of `package`, whether or not it is on disk yet.
  ///
  /// The directory hint is decided from the name, never from the disk, so the URL compares
  /// equal before and after the install: a compiled Core ML model is always a folder.
  public func artifact(of package: ModelPackage) -> URL {
    let isFolder = (package.artifactName as NSString).pathExtension == "mlmodelc"
    return folder(for: package.id).appending(
      path: package.artifactName, directoryHint: isFolder ? .isDirectory : .notDirectory)
  }

  /// A Hugging Face model's compiled folder at `revision`: see `ModelPackage.huggingFace`.
  public func compiled(for id: String, revision: String) -> URL {
    folder(for: id).appending(path: "\(revision).mlmodelc", directoryHint: .isDirectory)
  }

  /// Bytes on disk under the root, for a Models pane's footer.
  public func diskUsage() -> Int64 {
    guard
      let walker = FileManager.default.enumerator(
        at: root, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
    else { return 0 }
    var total: Int64 = 0
    for case let url as URL in walker {
      let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
      if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
    }
    return total
  }
}
