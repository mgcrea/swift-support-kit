# Feedback Prompt Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A one-time, passive card that asks each Pro user what the app should do better, in the kit, with Cadence as the first adopter.

**Architecture:** `FeedbackPrompt` (Foundation + Observation, in `SupportKit`) owns the decision and three `UserDefaults` keys. `FeedbackPromptCard` (in `SupportKitUI`) draws it and opens the existing web form. An app records a milestone, tells the prompt when the rating ask fired, and places the card.

**Tech Stack:** Swift 6, swift-testing, SwiftUI, a hand-written `.xcstrings` catalog.

**Spec:** `docs/superpowers/specs/2026-11-19-feedback-prompt-design.md`

## Global Constraints

- Platform floor macOS 26 / iOS 26. `SupportKit` stays free of SwiftUI.
- No networking: the card hands a URL to `openURL`.
- Every string the card draws goes through `localized(_:)` with an entry marked `manual`, `"generatesSymbol": false`, and a French translation.
- Threshold default 5. Keys `<prefix>.feedback.milestones`, `.due`, `.resolved`.
- The kit checkout has foreign uncommitted edits in `README.md` and `Tests/SupportKitDrivingTests/PointerDeliveryTests.swift`. Never stage them.
- In Cadence: nothing shows under `ProcessInfo.isRunningTests` or `DemoSeed.isEnabled`.

## Review Focus

- A free user who transcribes 20 times then buys: the count starts at purchase, the card is due 5 Pro transcriptions later, not at once.
- The rating ask and the 5th Pro milestone on the same transcription: the rating wins, the card is hidden this session and pending on the next launch.
- Pro lost (refund, reset purchase) while the card is due: the card is not drawn while not Pro.
- Dismiss, then update the app: nothing shows again.
- Two windows on the Mac: resolving in one hides the card in the other.

---

### Task 1: `FeedbackPrompt` in `SupportKit`

**Files:**
- Create: `Sources/SupportKit/FeedbackPrompt.swift`
- Test: `Tests/SupportKitTests/FeedbackPromptTests.swift`

**Interfaces — produces:**

```swift
@MainActor @Observable public final class FeedbackPrompt {
  public init(keyPrefix: String, threshold: Int = 5, defaults: UserDefaults = .standard)
  public func recordMilestone(isPro: Bool)
  public func noteReviewAsked()
  public private(set) var isPending: Bool   // due && !resolved && no rating ask this session
  public func resolve()
  public var milestoneCount: Int { get }
  public func reset()
}
```

- [ ] **Step 1:** Write the failing tests, each on a scratch `UserDefaults` suite as `ReviewPromptTests` does: not pending before the threshold; pending at the 5th Pro milestone; free milestones never count (20 free, then 4 Pro: not pending; 5th Pro: pending); pending survives a new instance on the same defaults; `noteReviewAsked()` hides it for this instance and a new instance shows it; `noteReviewAsked()` before the threshold milestone still hides it; `resolve()` clears it for this and every later instance, whatever is recorded after; `reset()` returns to a fresh state.
- [ ] **Step 2:** `swift test --filter FeedbackPromptTests` fails to compile.
- [ ] **Step 3:** Implement. `isPending` is a stored property recomputed after every mutation, so Observation sees it.
- [ ] **Step 4:** `swift test --filter FeedbackPromptTests` passes.
- [ ] **Step 5:** Commit `feat(SupportKit): FeedbackPrompt, a one-time ask for Pro users`.

### Task 2: `FeedbackPromptCard` in `SupportKitUI`

**Files:**
- Create: `Sources/SupportKitUI/FeedbackPromptCard.swift`
- Modify: `Sources/SupportKitUI/Resources/Localizable.xcstrings`
- Modify: `README.md` (a section beside `ReviewPrompt`'s; the install line to 1.28.0)

**Interfaces — produces:** `public struct FeedbackPromptCard: View { public init(app: SupportApp, prompt: FeedbackPrompt, isPro: Bool = true) }`. Draws nothing unless `prompt.isPending && isPro`.

Copy, exact:

| English key | French |
|---|---|
| `What should %@ do better?` | `Que devrait mieux faire %@ ?` |
| `Thanks for buying Pro. I read every message, and good ideas ship fast.` | `Merci d’avoir acheté Pro. Je lis chaque message, et les bonnes idées arrivent vite.` |
| `Dismiss` | `Fermer` |

"Send Feedback" reuses the existing entry. The Send button opens `app.feedbackURL(kind: .idea)` then calls `prompt.resolve()`; the close button (an `xmark`, accessibility label "Dismiss") calls `prompt.resolve()`. No background, no padding outside its own content.

- [ ] **Step 1:** Add the view and the three catalog entries.
- [ ] **Step 2:** `swift test` passes, the catalog drift and resolution suites included.
- [ ] **Step 3:** README: document both types; stage only this plan's hunks.
- [ ] **Step 4:** Commit `feat(SupportKitUI): FeedbackPromptCard`, then `docs: the feedback prompt, and the install line at 1.28.0`.
- [ ] **Step 5:** Tag `1.28.0` and push, after the owner says so.

### Task 3: Cadence adopts it

**Files (under `apps/apple`):**
- Modify: `CadenceShared/Services/Review.swift` (owns the `FeedbackPrompt` beside the `ReviewPrompt`)
- Modify: `CadenceShared/Services/TranscriptionCoordinator.swift:645`
- Create: `CadenceShared/Views/FeedbackAskCard.swift` (the kit card with Cadence's chrome, shared by both shells)
- Modify: `Cadence/Views/LibrarySidebar.swift:133` (above the Add Group bar, in the same inset)
- Modify: `CadenceMobile/MobileLibraryView.swift:394` (first section of the list)
- Modify: `Cadence.xcodeproj/project.pbxproj` (kit floor 1.28.0) and `Package.resolved`
- Modify: `CHANGELOG.md`

**Interfaces:** `Review.recordSuccessfulTranscription(isPro: Bool)` records both milestones and calls `feedback.noteReviewAsked()` when the rating ask is raised. `Review.feedback: FeedbackPrompt?` is nil under tests and in demo mode.

- [ ] **Step 1:** Wire `Review`, the coordinator call (`EntitlementStore.shared.access.isPro`), and the two placements.
- [ ] **Step 2:** `make build` and `make build-ios` pass.
- [ ] **Step 3:** `make test` passes; goldens unchanged.
- [ ] **Step 4:** Look at the card on both platforms with a debug default that marks it due.
- [ ] **Step 5:** CHANGELOG entry; commit `feat: ask Pro users once what Cadence should do better`.
