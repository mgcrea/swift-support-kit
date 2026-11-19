import Foundation
import Testing

@testable import SupportKit

/// A private `UserDefaults` per test, as `ReviewPromptTests` has.
private func scratchDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
  let defaults = UserDefaults(suiteName: name)!
  defaults.removePersistentDomain(forName: name)
  return defaults
}

@MainActor
@Suite("FeedbackPrompt")
struct FeedbackPromptTests {
  private func record(_ count: Int, isPro: Bool, on prompt: FeedbackPrompt) {
    for _ in 0..<count { prompt.recordMilestone(isPro: isPro) }
  }

  @Test("is not pending before the threshold")
  func silentBeforeThreshold() {
    let prompt = FeedbackPrompt(keyPrefix: "t", defaults: scratchDefaults())
    #expect(prompt.isPending == false)
    record(4, isPro: true, on: prompt)
    #expect(prompt.isPending == false)
  }

  @Test("is pending from the fifth Pro milestone, the default threshold")
  func pendingAtThreshold() {
    let prompt = FeedbackPrompt(keyPrefix: "t", defaults: scratchDefaults())
    record(5, isPro: true, on: prompt)
    #expect(prompt.isPending == true)
    #expect(prompt.milestoneCount == 5)
  }

  /// The count starts at the purchase: somebody who used the free app for months
  /// and bought Pro today is not asked today.
  @Test("milestones before Pro never count")
  func freeMilestonesDoNotCount() {
    let prompt = FeedbackPrompt(keyPrefix: "t", defaults: scratchDefaults())
    record(20, isPro: false, on: prompt)
    #expect(prompt.milestoneCount == 0)
    record(4, isPro: true, on: prompt)
    #expect(prompt.isPending == false)
    record(1, isPro: true, on: prompt)
    #expect(prompt.isPending == true)
  }

  /// A card, not an alert: it waits until it is answered or closed.
  @Test("stays pending across launches until resolved")
  func pendingPersists() {
    let defaults = scratchDefaults()
    record(5, isPro: true, on: FeedbackPrompt(keyPrefix: "t", defaults: defaults))
    #expect(FeedbackPrompt(keyPrefix: "t", defaults: defaults).isPending == true)
  }

  @Test("a rating ask hides it for the session, and only for the session")
  func reviewAskHidesForTheSession() {
    let defaults = scratchDefaults()
    let first = FeedbackPrompt(keyPrefix: "t", defaults: defaults)
    record(5, isPro: true, on: first)
    first.noteReviewAsked()
    #expect(first.isPending == false)
    #expect(FeedbackPrompt(keyPrefix: "t", defaults: defaults).isPending == true)
  }

  /// Both asks landing on one success: the rating wins, and the card still
  /// becomes due, for the next launch.
  @Test("a rating ask before the threshold milestone still hides it")
  func reviewAskBeforeTheThreshold() {
    let defaults = scratchDefaults()
    let first = FeedbackPrompt(keyPrefix: "t", defaults: defaults)
    record(4, isPro: true, on: first)
    first.noteReviewAsked()
    record(1, isPro: true, on: first)
    #expect(first.isPending == false)
    #expect(FeedbackPrompt(keyPrefix: "t", defaults: defaults).isPending == true)
  }

  @Test("resolved is for good")
  func resolveIsPermanent() {
    let defaults = scratchDefaults()
    let first = FeedbackPrompt(keyPrefix: "t", defaults: defaults)
    record(5, isPro: true, on: first)
    first.resolve()
    #expect(first.isPending == false)
    record(10, isPro: true, on: first)
    #expect(first.isPending == false)

    let second = FeedbackPrompt(keyPrefix: "t", defaults: defaults)
    record(10, isPro: true, on: second)
    #expect(second.isPending == false)
  }

  /// One window's card answered is every window's card gone.
  @Test("two instances on one defaults domain agree once either is asked")
  func resolveReachesAnotherInstance() {
    let defaults = scratchDefaults()
    let a = FeedbackPrompt(keyPrefix: "t", defaults: defaults)
    record(5, isPro: true, on: a)
    a.resolve()
    #expect(FeedbackPrompt(keyPrefix: "t", defaults: defaults).isPending == false)
  }

  @Test("two apps sharing a defaults domain do not collide")
  func keyPrefixIsolates() {
    let defaults = scratchDefaults()
    record(5, isPro: true, on: FeedbackPrompt(keyPrefix: "alpha", defaults: defaults))
    let beta = FeedbackPrompt(keyPrefix: "beta", defaults: defaults)
    #expect(beta.milestoneCount == 0)
    #expect(beta.isPending == false)
  }

  @Test("reset clears the stored state")
  func resetClears() {
    let prompt = FeedbackPrompt(keyPrefix: "t", threshold: 1, defaults: scratchDefaults())
    record(1, isPro: true, on: prompt)
    prompt.resolve()
    prompt.noteReviewAsked()
    prompt.reset()
    #expect(prompt.milestoneCount == 0)
    #expect(prompt.isPending == false)
    record(1, isPro: true, on: prompt)
    #expect(prompt.isPending == true)
  }
}
