import Foundation
import Observation

/// Decides when to ask a Pro user, once, what the app should do better.
///
/// Written for the app that sold best and heard least: two written reviews, and
/// a feedback form in the Help menu and in Settings, where only somebody already
/// looking for it finds it. The apps collect nothing, so there is no address to
/// write to. The app is the only place a buyer can be asked.
///
/// It is the sibling of `ReviewPrompt` and not a mode of it, because the rules
/// differ on every point. That ask is per version, throttled by the system, and
/// may show nothing. This one is once, ever, for somebody who has paid, and it
/// is a card the app places rather than an alert: it waits until it is answered
/// or closed, and then never comes back, update or not.
///
/// Three rules do the work:
///
/// - **Only milestones reached as Pro count.** The count starts at the purchase,
///   so somebody who used the free app for months and bought today is not asked
///   today. They are asked once Pro has been useful a few times.
/// - **Never in a session where the rating ask fired.** Two asks in one sitting
///   is the nagging this must not become. The card stays due and shows on the
///   next launch.
/// - **Resolved is for good.** Answering and closing are the same event here.
///
/// ## Usage
///
/// ```swift
/// let feedback = FeedbackPrompt(keyPrefix: "silhouette")
///
/// // when an export finishes
/// feedback.recordMilestone(isPro: store.isUnlocked)
/// if review.recordMilestoneAndShouldAsk() {
///   feedback.noteReviewAsked()
///   requestReview()
/// }
///
/// // where the card goes (SupportKitUI)
/// FeedbackPromptCard(app: .silhouette, prompt: feedback, isPro: store.isUnlocked)
/// ```
@MainActor
@Observable
public final class FeedbackPrompt {
  /// True while the card should be on screen.
  ///
  /// Stored, and rewritten after every change, rather than computed from
  /// `UserDefaults`: Observation tracks stored properties, and a view reading a
  /// computed one over defaults is never told that it changed.
  public private(set) var isPending = false

  @ObservationIgnored private let keyPrefix: String
  /// Pro milestones before the ask.
  ///
  /// Five rather than `ReviewPrompt`'s three: a rating takes one tap, an answer
  /// to this takes a few sentences, and somebody has more to say about the fifth
  /// use than about the third.
  @ObservationIgnored private let threshold: Int
  @ObservationIgnored private let defaults: UserDefaults

  /// Set for the rest of the process once the rating ask fires. Not persisted,
  /// for the reason `ReviewPrompt.paywallSeenThisSession` is not: it is about
  /// this sitting.
  @ObservationIgnored private var reviewAskedThisSession = false

  public init(keyPrefix: String, threshold: Int = 5, defaults: UserDefaults = .standard) {
    self.keyPrefix = keyPrefix
    self.threshold = threshold
    self.defaults = defaults
    refresh()
  }

  private var milestoneKey: String { "\(keyPrefix).feedback.milestones" }
  private var dueKey: String { "\(keyPrefix).feedback.due" }
  private var resolvedKey: String { "\(keyPrefix).feedback.resolved" }

  /// Records one successful outcome.
  ///
  /// A milestone reached without Pro is not counted at all, so the count means
  /// "successes since this person paid".
  ///
  /// *Due* is stored once reached, and not re-derived from the count, so an app
  /// that later raises its threshold does not take the card back from somebody
  /// who was already shown it.
  public func recordMilestone(isPro: Bool) {
    guard isPro else { return }
    guard !defaults.bool(forKey: resolvedKey) else { return }
    let count = defaults.integer(forKey: milestoneKey) + 1
    defaults.set(count, forKey: milestoneKey)
    if count >= threshold { defaults.set(true, forKey: dueKey) }
    refresh()
  }

  /// Call when the rating ask is raised, whether or not the system shows it.
  public func noteReviewAsked() {
    reviewAskedThisSession = true
    refresh()
  }

  /// The person answered, or closed the card. Either way it is over.
  public func resolve() {
    defaults.set(true, forKey: resolvedKey)
    refresh()
  }

  /// How many Pro milestones have been recorded, for a debug readout.
  public var milestoneCount: Int { defaults.integer(forKey: milestoneKey) }

  /// Clears the stored state. Unconditional, as `ReviewPrompt.reset()` is, so an
  /// app can wire it to a hidden developer action.
  public func reset() {
    defaults.removeObject(forKey: milestoneKey)
    defaults.removeObject(forKey: dueKey)
    defaults.removeObject(forKey: resolvedKey)
    reviewAskedThisSession = false
    refresh()
  }

  private func refresh() {
    let pending =
      defaults.bool(forKey: dueKey) && !defaults.bool(forKey: resolvedKey)
      && !reviewAskedThisSession
    // Written only on a change: an Observation write wakes every view reading
    // it, and this runs on every milestone.
    if pending != isPending { isPending = pending }
  }
}
