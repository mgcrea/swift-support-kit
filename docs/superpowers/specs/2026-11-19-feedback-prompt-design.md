# Feedback prompt: a one-time ask for Pro users

2026-11-19. Approved in conversation the same day.

## Why

Cadence sells well and hears nothing: two written reviews, and a feedback form that sits in
the Help menu and Settings where only somebody looking for it finds it. The apps collect no
data, so there is no address to write to; the app is the only place a buyer can be asked.
The other apps in the fleet are in the same position, which is why this lives in the kit.

## Goals

- Ask each Pro user once, ever, what the app should do better.
- Ask without interrupting: a passive card the host places, never an alert or a sheet.
- Collect nothing in the app. The card opens the existing web feedback form.
- Reusable: an app adopts it with a key prefix, one call at its milestone and one view.

## Non-goals and anti-goals

- No "remind me later", no second ask after an update, no ask for free users.
- Never in the same session as the rating ask. Two asks in one sitting is the nagging this
  must not become.
- No networking and no new stored data beyond three `UserDefaults` keys.

## Approaches

1. **A sibling of `ReviewPrompt`, plus an unstyled card** (picked). Same shape as the type
   apps already use, its own rules, testable without a host.
2. An alert or sheet at the milestone. Dropped: it interrupts the work that just succeeded.
3. Folding it into `ReviewPrompt`. Dropped: that ask is per version and throttled by the
   system; this one is once ever and Pro only. One type would carry two sets of rules.

## Design

### `SupportKit`: `FeedbackPrompt`

`@MainActor @Observable public final class`, Foundation and Observation only.

- `init(keyPrefix:threshold: = 5, defaults: = .standard)`.
- `recordMilestone(isPro:)` counts a successful outcome only while `isPro` is true, so the
  count starts at purchase (or, for an existing buyer, at the update that brought this).
  At the threshold it marks the ask *due*, persisted.
- `noteReviewAsked()` sets a session flag, not persisted: the card stays hidden for the rest
  of this process and appears on the next launch.
- `isPending: Bool` is true when due, not resolved, and no rating ask happened this session.
  Observable, so a view watching it redraws.
- `resolve()` is called on tap and on dismiss alike. Persisted; nothing shows again.
- `reset()` for a debug action and for tests, as `ReviewPrompt` has.

Keys: `<prefix>.feedback.milestones`, `<prefix>.feedback.due`, `<prefix>.feedback.resolved`.

### `SupportKitUI`: `FeedbackPromptCard`

`FeedbackPromptCard(app:prompt:)`. Draws a title ("What should <displayName> do better?"),
one line ("Thanks for buying Pro. I read every message, and good ideas ship fast."), a Send
Feedback button and a close button. Renders nothing unless `prompt.isPending`. No background
of its own, for the reason `FeedbackLink` gives; the host applies its chrome.

Send Feedback opens `app.feedbackURL(kind: .idea)` through `openURL` and resolves the
prompt. Close resolves it. Strings are in the module's catalog, English and French.

### Adopting it (Cadence is the first)

- Record the milestone where the rating milestone is recorded, passing the Pro state.
- Call `noteReviewAsked()` when the rating ask is raised.
- Place the card: bottom of the library sidebar on the Mac, top of the library list on iOS.
- Off under tests and in demo mode, so screenshots and goldens do not change.

## Left to the builder

The card's exact metrics, and the host's chrome in each app.
