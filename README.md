# swift-support-kit

[![swift](https://img.shields.io/badge/swift-6.0-orange.svg)](https://swift.org)
[![platforms](https://img.shields.io/badge/platforms-macOS%2015%20%7C%20iOS%2017-lightgrey.svg)](#requirements)
[![license](https://img.shields.io/github/license/mgcrea/swift-support-kit.svg)](./LICENSE)

Feedback, support links and App Store rating prompts for Mac and iOS apps — **without the app
ever opening a network connection**.

The app builds a URL and hands it to the system. The website does the sending. That single
constraint is what lets a sandboxed, no-network, "Data Not Collected" app offer a real feedback
form without giving any of that up.

```swift
import SupportKit

extension SupportApp {
    static let silhouette = SupportApp(
        slug: "silhouette",
        displayName: "Silhouette",
        siteURL: URL(string: "https://silhouette.mgcrea.io")!,
        trackerURL: URL(string: "https://github.com/mgcrea/support/tree/main/silhouette")!
    )
}

// https://silhouette.mgcrea.io/feedback/?v=1&app=silhouette&kind=bug
//   &av=1.4%20(168)&os=macOS%2026.4&hw=Mac16,10&lang=en
openURL(SupportApp.silhouette.feedbackURL(kind: .bug))
```

## Why not just POST it

Because for a lot of apps you cannot, and for the rest you should not want to.

- **Entitlements.** An app that ships without `com.apple.security.network.client` cannot make
  the request at all. If its privacy page invites users to verify that with
  `codesign -d --entitlements -`, adding the entitlement to power a feedback form breaks a
  published, checkable promise.
- **Privacy labels.** An in-app POST of user-typed text makes the App Store label *User
  Content*, plus *Contact Info → Email* if the address is collected in-app. Handing off a URL
  keeps every listing at **Data Not Collected**, because the app genuinely collects nothing.
- **It is inspectable.** A POST can only be described to the user. A URL is sitting in the
  address bar, in full, before they press anything. That is a property you can actually prove.

The corollary is a rule for the receiving page: **render the diagnostics as visible, editable,
deletable fields.** Never hidden inputs. The moment they are hidden, "you can see everything it
sends" stops being true and the whole argument collapses.

## What it sends

Four facts, and it is worth reading the list for what is *not* there:

| param | example | |
| --- | --- | --- |
| `v` | `1` | contract version — the receiving page rejects what it does not know |
| `app` | `silhouette` | slug: tracker label, query key and database key, one string |
| `kind` | `bug` | `bug` \| `idea` \| `question` |
| `av` | `1.4 (168)` | short version and build |
| `os` | `macOS 26.4` | composed, never `operatingSystemVersionString` |
| `hw` | `Mac16,10` | model identifier |
| `lang` | `en` | language only, never the region |
| `s` | optional | subject seed, ≤ 120 chars, truncated on a grapheme boundary |

No username, no hostname, no file or folder paths, no document names, no serial number, **no
persistent identifier of any kind**. Two reports from the same machine are not linkable by
anything in this list. A test asserts it.

## Install

```swift
.package(url: "https://github.com/mgcrea/swift-support-kit.git", .upToNextMinor(from: "1.0.0"))
```

Two products. `SupportKit` is Foundation-only, so it unit-tests without a host app and imports
from non-UI modules. `SupportKitUI` adds the SwiftUI surface.

## The Help menu

```swift
import SupportKitUI

.commands {
    SupportCommands(app: .silhouette, preferIssueTracker: false) { showHelp = true }
}
```

`preferIssueTracker` orders the two links. Set it **true** for developer-facing apps, where a
public, searchable, subscribable GitHub issue is a feature. Set it **false** where a GitHub
account is a wall — nobody posts a client's unreleased artwork to a public tracker to report a
bug in it.

The ⌘/ help action stays a closure. Every app already routes it its own way, and replacing that
plumbing is not this package's job.

## Rating prompts

Wrapping `requestReview` in the two rules that decide *who* gets asked:

```swift
@Environment(\.requestReview) private var requestReview
private let prompt = ReviewPrompt(keyPrefix: "silhouette")

prompt.notePaywallShown()                                   // when the paywall appears
if prompt.recordMilestoneAndShouldAsk() { requestReview() }  // when an export succeeds
```

- **Only after a successful outcome** — not on launch, not on a timer. The user has just got the
  thing they came for.
- **Never in a session where the paywall appeared.** Someone mid-friction asked to rate the app
  writes the review that friction would write. For an app introducing a gate where there was
  none, the *first* review it ever gets should not be that person's.

Asks at most once per app version. Apple throttles `requestReview` to roughly three prompts a
year and may show nothing at all, so nothing here treats "asked" as "reviewed".

## Styling

`FeedbackLink` and `IssueTrackerLink` render a bare `Label` — no background, no glass, no accent
colour, no padding. Glass adoption differs wildly between apps, and a component that imposed
`.glassEffect` would look pasted-in wherever it landed in an app that uses none. The host styles
it:

```swift
FeedbackLink(app: .silhouette)
    .buttonStyle(.plain)
    .padding(.horizontal, 12)
    .background(.thinMaterial, in: .capsule)
```

For the same reason there is no shared `HelpView`. Apps have bespoke help sheets worth keeping.

## Requirements

macOS 15+ / iOS 17+, Swift 6. The floor is low on purpose: this package builds URLs, reads two
sysctls and touches `UserDefaults`, so nothing in it needs a newer OS, and raising the floor to
match the newest consuming app would lock out the oldest for no gain.

## Notes for anyone reading the source

Three traps are handled, each of which fails by returning a plausible **wrong answer** rather
than an error:

- **`hw.model` is the wrong sysctl on iOS.** It gives a board id like `D74AP`; `hw.machine`
  gives `iPhone17,1`. The key is compile-switched.
- **The Simulator reports the host Mac.** `SIMULATOR_MODEL_IDENTIFIER` wins when set.
- **`mailto:` is not an HTTP query.** `+` is a literal plus, not a space, and line breaks must be
  CRLF. Reusing a GitHub issue URL's query string in a mail draft produces a subject reading
  `[silhouette]+`. Everything is built through `URLComponents`, which encodes a space as `%20`.

## License

MIT — see [LICENSE](./LICENSE).
