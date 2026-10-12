import Foundation

@testable import SupportKitStore

/// A private `UserDefaults` per test, so these never touch the real domain and never depend
/// on each other's leftovers.
func scratchDefaults() -> UserDefaults {
  let name = "ProStoreTests.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: name)!
  defaults.removePersistentDomain(forName: name)
  return defaults
}

@MainActor
func makeStore(
  _ script: StoreScript, _ configure: (inout ProStore.Configuration) -> Void = { _ in }
) -> ProStore {
  var configuration = ProStore.Configuration(productID: "pro", defaults: scratchDefaults())
  configure(&configuration)
  return ProStore(configuration, client: script.client, isTestHost: false)
}

/// Collects `onChange` calls. A class, because an isolated closure cannot capture a `var`.
@MainActor
final class Recorder {
  var values: [Bool] = []
}

/// Polls until `condition` holds, for effects that arrive through the updates listener or
/// land in the scripted store.
@MainActor
func eventually(_ condition: () async -> Bool) async -> Bool {
  for _ in 0..<200 {
    if await condition() { return true }
    try? await Task.sleep(for: .milliseconds(5))
  }
  return await condition()
}
