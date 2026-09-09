import Foundation
import Testing

@testable import SupportKit

/// A private `UserDefaults` per test, so these never touch the real domain and
/// never depend on each other's leftovers.
private func scratchDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
  let defaults = UserDefaults(suiteName: name)!
  defaults.removePersistentDomain(forName: name)
  return defaults
}

@MainActor
@Suite("ReviewPrompt")
struct ReviewPromptTests {
  @Test("does not ask before the threshold")
  func silentBeforeThreshold() {
    let prompt = ReviewPrompt(
      keyPrefix: "t", threshold: 3, defaults: scratchDefaults(), currentVersion: { "1.0" })
    #expect(prompt.recordMilestoneAndShouldAsk() == false)
    #expect(prompt.recordMilestoneAndShouldAsk() == false)
  }

  @Test("asks on the threshold milestone")
  func asksOnThreshold() {
    let prompt = ReviewPrompt(
      keyPrefix: "t", threshold: 3, defaults: scratchDefaults(), currentVersion: { "1.0" })
    _ = prompt.recordMilestoneAndShouldAsk()
    _ = prompt.recordMilestoneAndShouldAsk()
    #expect(prompt.recordMilestoneAndShouldAsk() == true)
  }

  @Test("asks at most once per version")
  func onlyOncePerVersion() {
    let prompt = ReviewPrompt(
      keyPrefix: "t", threshold: 1, defaults: scratchDefaults(), currentVersion: { "1.0" })
    #expect(prompt.recordMilestoneAndShouldAsk() == true)
    #expect(prompt.recordMilestoneAndShouldAsk() == false)
    #expect(prompt.recordMilestoneAndShouldAsk() == false)
  }

  @Test("asks again after the app updates")
  func asksAgainOnNewVersion() {
    let defaults = scratchDefaults()
    var version = "1.0"
    let prompt = ReviewPrompt(
      keyPrefix: "t", threshold: 1, defaults: defaults, currentVersion: { version })
    #expect(prompt.recordMilestoneAndShouldAsk() == true)
    version = "1.1"
    #expect(prompt.recordMilestoneAndShouldAsk() == true)
  }

  /// The rule that protects the first review the app ever gets.
  @Test("never asks in a session where the paywall appeared")
  func paywallSuppresses() {
    let prompt = ReviewPrompt(
      keyPrefix: "t", threshold: 1, defaults: scratchDefaults(), currentVersion: { "1.0" })
    prompt.notePaywallShown()
    #expect(prompt.recordMilestoneAndShouldAsk() == false)
    #expect(prompt.recordMilestoneAndShouldAsk() == false)
  }

  /// Suppression is about this sitting, not a permanent black mark — a new
  /// instance is a new session.
  @Test("paywall suppression does not persist across sessions")
  func suppressionIsNotPersisted() {
    let defaults = scratchDefaults()
    let first = ReviewPrompt(
      keyPrefix: "t", threshold: 1, defaults: defaults, currentVersion: { "1.0" })
    first.notePaywallShown()
    #expect(first.recordMilestoneAndShouldAsk() == false)

    let second = ReviewPrompt(
      keyPrefix: "t", threshold: 1, defaults: defaults, currentVersion: { "1.0" })
    #expect(second.recordMilestoneAndShouldAsk() == true)
  }

  /// The counter increments before the guards, so meeting a paywall on the
  /// third success costs the ask, not the count.
  @Test("counts a suppressed milestone so the next one can ask")
  func suppressedMilestoneStillCounts() {
    let defaults = scratchDefaults()
    let blocked = ReviewPrompt(
      keyPrefix: "t", threshold: 3, defaults: defaults, currentVersion: { "1.0" })
    _ = blocked.recordMilestoneAndShouldAsk()
    _ = blocked.recordMilestoneAndShouldAsk()
    blocked.notePaywallShown()
    #expect(blocked.recordMilestoneAndShouldAsk() == false)
    #expect(blocked.milestoneCount == 3)

    let next = ReviewPrompt(
      keyPrefix: "t", threshold: 3, defaults: defaults, currentVersion: { "1.0" })
    #expect(next.recordMilestoneAndShouldAsk() == true)
  }

  @Test("two apps sharing a defaults domain do not collide")
  func keyPrefixIsolates() {
    let defaults = scratchDefaults()
    let a = ReviewPrompt(
      keyPrefix: "alpha", threshold: 2, defaults: defaults, currentVersion: { "1.0" })
    let b = ReviewPrompt(
      keyPrefix: "beta", threshold: 2, defaults: defaults, currentVersion: { "1.0" })
    _ = a.recordMilestoneAndShouldAsk()
    #expect(b.milestoneCount == 0)
    #expect(b.recordMilestoneAndShouldAsk() == false)
  }

  @Test("reset clears the stored state")
  func resetClears() {
    let prompt = ReviewPrompt(
      keyPrefix: "t", threshold: 1, defaults: scratchDefaults(), currentVersion: { "1.0" })
    #expect(prompt.recordMilestoneAndShouldAsk() == true)
    prompt.reset()
    #expect(prompt.milestoneCount == 0)
    #expect(prompt.recordMilestoneAndShouldAsk() == true)
  }
}
