import Foundation

/// Decides when to ask for an App Store rating.
///
/// Generalised from the one app in a nine-app portfolio that had a `requestReview`
/// call site at all. The other eight had the API available and never called it,
/// and between them they had collected **two written reviews, ever** — too few
/// for the App Store to show a rating overview on any of their pages, so the only
/// social proof a visitor saw was none.
///
/// Two rules do the work, and both are about *who* gets asked rather than how
/// often:
///
/// - **Only after a successful outcome.** Not on launch, not on a timer. The user
///   has just got the thing they came for and has something to show for it.
/// - **Never in a session where the paywall appeared.** Someone who just hit a
///   gate is mid-friction, and asking them to rate the app is asking for the
///   review that friction would write. This matters most for an app that
///   introduces a gate where there never was one: the *first* review it ever
///   gets should not be that person's.
///
/// Apple throttles `requestReview` to roughly three prompts a year per user and
/// may show nothing at all, so this is a request rather than a guarantee — which
/// is also why nothing here treats "asked" as "reviewed".
///
/// ## Usage
///
/// ```swift
/// @Environment(\.requestReview) private var requestReview
/// private let prompt = ReviewPrompt(keyPrefix: "silhouette")
///
/// // when the paywall is shown
/// prompt.notePaywallShown()
///
/// // when an export finishes
/// if prompt.recordMilestoneAndShouldAsk() { requestReview() }
/// ```
@MainActor
public final class ReviewPrompt {
    /// Namespaces the `UserDefaults` keys. Use the app's slug.
    private let keyPrefix: String
    /// Successful outcomes before the first ask.
    ///
    /// Three rather than one: a single success proves the app ran, not that it
    /// was useful enough to come back to.
    private let threshold: Int
    private let defaults: UserDefaults
    private let currentVersion: () -> String

    /// Set for the rest of the process once a paywall is shown.
    ///
    /// Deliberately **not** persisted: the suppression is about this sitting, not
    /// a permanent black mark against someone who once looked at the price.
    private var paywallSeenThisSession = false

    public init(
        keyPrefix: String,
        threshold: Int = 3,
        defaults: UserDefaults = .standard,
        currentVersion: @escaping () -> String = { ReviewPrompt.shortVersion() }
    ) {
        self.keyPrefix = keyPrefix
        self.threshold = threshold
        self.defaults = defaults
        self.currentVersion = currentVersion
    }

    private var milestoneKey: String { "\(keyPrefix).review.milestones" }
    private var askedVersionKey: String { "\(keyPrefix).review.askedForVersion" }

    /// Call when a paywall, upgrade sheet or price is shown.
    public func notePaywallShown() {
        paywallSeenThisSession = true
    }

    /// Records one successful outcome and reports whether this is the moment to ask.
    ///
    /// Counts every milestone but asks at most once per app version, so someone
    /// who exports daily is not re-asked after each success — only after an
    /// update that changed the version they were last asked on.
    ///
    /// The counter is incremented **before** the guards, on purpose: a user who
    /// meets the paywall on their third success should be asked on their fourth,
    /// not have the third not count.
    public func recordMilestoneAndShouldAsk() -> Bool {
        let count = defaults.integer(forKey: milestoneKey) + 1
        defaults.set(count, forKey: milestoneKey)

        guard !paywallSeenThisSession else { return false }
        guard count >= threshold else { return false }

        let version = currentVersion()
        guard defaults.string(forKey: askedVersionKey) != version else { return false }
        defaults.set(version, forKey: askedVersionKey)
        return true
    }

    /// How many successful outcomes have been recorded, for a debug readout.
    public var milestoneCount: Int { defaults.integer(forKey: milestoneKey) }

    public static func shortVersion(bundle: Bundle = .main) -> String {
        bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Clears the stored state. Exposed unconditionally rather than behind
    /// `#if DEBUG` so a consuming app can wire it to a hidden developer action
    /// and so the tests can run against a release build of the package.
    public func reset() {
        defaults.removeObject(forKey: milestoneKey)
        defaults.removeObject(forKey: askedVersionKey)
        paywallSeenThisSession = false
    }
}
