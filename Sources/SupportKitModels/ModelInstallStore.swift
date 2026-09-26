import Foundation
import Observation

/// What is installed and what is downloading, per model id. The part of a model store every
/// app shares; which model is active, and for what, stays in the app, which wraps this.
///
/// It keeps two things apart that a single status would conflate: what an install is doing
/// (`state(of:)`) and which finished model can be loaded right now (`installedURL(of:)`).
/// While an outdated model updates, and after its update fails, the old one is still on disk
/// and still the one to load.
@Observable
@MainActor
public final class ModelInstallStore {
  public enum InstallState: Equatable, Sendable {
    case notInstalled
    case downloading(received: Int64, total: Int64)
    case verifying
    case compiling
    case ready(URL)
    /// Installed and usable, but the package now names a newer artifact.
    case outdated(URL)
    case failed(String)
  }

  public private(set) var states: [String: InstallState] = [:]
  /// The finished model each id can load right now. See the type's comment.
  private var installed: [String: URL] = [:]
  /// Why the last install of an id failed, until the next one starts. For an installed model
  /// whose update failed, this is the only place the reason lives: its state goes back to
  /// `.outdated` so it stays usable and removable.
  private var errors: [String: String] = [:]
  @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
  /// Bumped every time an id starts a new install or is uninstalled, so a cancelled
  /// install's progress and result are recognisably stale once superseded: `tasks[id]`
  /// alone only says "something is running for this id", not "this is the run that is
  /// reporting in", and a fresh install can start before the old one has unwound.
  @ObservationIgnored private var generations: [String: Int] = [:]
  @ObservationIgnored private var packages: [String: ModelPackage] = [:]
  @ObservationIgnored private let installer: ModelInstaller
  @ObservationIgnored private let describe: @Sendable (any Error) -> String

  /// Reads what is on disk for every package, and sweeps any staging folder a quit or a crash
  /// left mid-download. No network.
  ///
  /// `describe` turns a failure into the message `state(of:)` carries; the default is the
  /// error's `localizedDescription`.
  public init(
    installer: ModelInstaller, packages: [ModelPackage],
    describe: @escaping @Sendable (any Error) -> String = { $0.localizedDescription }
  ) {
    self.installer = installer
    self.describe = describe
    installer.locations.excludeFromBackup()
    for package in packages {
      self.packages[package.id] = package
      try? FileManager.default.removeItem(at: installer.locations.staging(for: package.id))
      let state = diskState(of: package)
      states[package.id] = state
      switch state {
      case .ready(let url), .outdated(let url): installed[package.id] = url
      default: break
      }
    }
  }

  public var locations: ModelLocations { installer.locations }

  // MARK: - State

  public func state(of id: String) -> InstallState {
    states[id] ?? .notInstalled
  }

  /// The finished model `id` can load now, independent of any update in progress.
  public func installedURL(of id: String) -> URL? {
    installed[id]
  }

  /// Why the last install of `id` failed, or nil once a new one starts or it is removed.
  public func lastError(of id: String) -> String? {
    errors[id]
  }

  /// What an id shows when nothing is running: ready, outdated or not installed, from what is
  /// usable rather than from the disk.
  private func restingState(of id: String) -> InstallState {
    guard let url = installed[id] else { return .notInstalled }
    guard let package = packages[id] else { return .ready(url) }
    return url.lastPathComponent == package.artifactName ? .ready(url) : .outdated(url)
  }

  private func diskState(of package: ModelPackage) -> InstallState {
    let current = locations.artifact(of: package)
    if FileManager.default.fileExists(atPath: current.path()) { return .ready(current) }
    let folder = locations.folder(for: package.id)
    let children =
      (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))
      ?? []
    let ext = (package.artifactName as NSString).pathExtension
    // Rebuilt from `folder` (not the enumerated URL) so it matches byte-for-byte what
    // `locations` would produce: `contentsOfDirectory` can hand back a URL with `/var`
    // resolved to `/private/var`, which otherwise compares unequal.
    if !ext.isEmpty, let older = children.first(where: { $0.pathExtension == ext }) {
      return .outdated(
        folder.appending(
          path: older.lastPathComponent,
          directoryHint: ext == "mlmodelc" ? .isDirectory : .notDirectory))
    }
    return .notInstalled
  }

  // MARK: - Installing

  /// Starts (or returns the running) install of `package`. The returned task finishes when
  /// the model is ready, failed or cancelled; it never throws. Does nothing for a model that
  /// is already ready; an outdated one is updated.
  ///
  /// `onFinish` runs on the main actor once the install ends, unless an uninstall or a newer
  /// install has superseded it by then: that is where an app activates a first model or
  /// drops a loaded one whose files were replaced.
  @discardableResult
  public func install(
    _ package: ModelPackage,
    onFinish: @escaping @MainActor (Result<URL, any Error>) -> Void = { _ in }
  ) -> Task<Void, Never> {
    let id = package.id
    if let running = tasks[id] { return running }
    packages[id] = package
    if case .ready = state(of: id) { return Task {} }
    let installer = self.installer
    let generation = (generations[id] ?? 0) + 1
    generations[id] = generation
    errors[id] = nil
    states[id] = .downloading(received: 0, total: package.totalBytes)
    let task = Task { [weak self] in
      let result: Result<URL, any Error>
      do {
        let url = try await installer.install(package) { [weak self] update in
          Task { @MainActor in self?.apply(update, to: id, generation: generation) }
        }
        result = .success(url)
      } catch {
        result = .failure(error)
      }
      guard let self, self.finish(id, result: result, generation: generation) else { return }
      onFinish(result)
    }
    tasks[id] = task
    return task
  }

  public func cancel(_ id: String) {
    tasks[id]?.cancel()
  }

  /// Cancels any install and deletes the model's folder.
  public func uninstall(_ id: String) {
    tasks[id]?.cancel()
    tasks[id] = nil
    // Invalidate any run still unwinding after cancellation, so its late progress or result
    // (which can arrive after a *new* install has already started) is ignored instead of
    // clobbering the reinstall.
    generations[id, default: 0] += 1
    try? FileManager.default.removeItem(at: locations.folder(for: id))
    installed[id] = nil
    errors[id] = nil
    states[id] = .notInstalled
  }

  private func apply(_ update: InstallProgress, to id: String, generation: Int) {
    // Superseded, or arriving after `finish`: a stale update.
    guard generations[id] == generation, tasks[id] != nil else { return }
    switch update {
    case .downloading(let received, let total):
      states[id] = .downloading(received: received, total: total)
    case .verifying:
      states[id] = .verifying
    case .compiling:
      states[id] = .compiling
    }
  }

  /// Records the result, and returns false for a stale one it ignored.
  private func finish(_ id: String, result: Result<URL, any Error>, generation: Int) -> Bool {
    guard generations[id] == generation else { return false }
    tasks[id] = nil
    switch result {
    case .success(let url):
      installed[id] = url
      states[id] = .ready(url)
    case .failure(let error) where error is CancellationError:
      states[id] = restingState(of: id)
    case .failure(let error):
      let message = describe(error)
      errors[id] = message
      // A failed update leaves the old model in place: it stays usable and removable, and
      // the message rides alongside instead of replacing it.
      states[id] = installed[id] == nil ? .failed(message) : restingState(of: id)
    }
    return true
  }
}
