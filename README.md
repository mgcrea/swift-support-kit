# swift-support-kit

[![swift](https://img.shields.io/badge/swift-6.0-orange.svg)](https://swift.org)
[![platforms](https://img.shields.io/badge/platforms-macOS%2026%20%7C%20iOS%2026-lightgrey.svg)](#requirements)
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
.package(url: "https://github.com/mgcrea/swift-support-kit.git", .upToNextMinor(from: "1.9.0"))
```

Five products. `SupportKit` is Foundation-only, so it unit-tests without a host app and imports
from non-UI modules. `SupportKitUI` adds the SwiftUI surface. `SupportKitSettings` adds the
settings scaffold, kept separate because it is the part that will churn. `SupportKitMenuBar`
adds the menu bar panel, which is macOS-only. `SupportKitToolbar` adds the two-line toolbar
controls, also macOS-only, and kept apart because it is the one module that draws glass — see
[Styling](#styling).

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

## Settings

The sidebar, the persisted pane, the accessibility identifiers and the deep-linking, once. The
app supplies only its pane bodies.

```swift
import SupportKitSettings

enum SettingsPane: String, SupportKitSettings.SettingsPane {
    case general, activity, about, licence

    var title: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .activity: "Activity"
        case .about: "About"
        case .licence: "Licence"
        }
    }
    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .activity: "list.bullet.rectangle"
        case .about: "info.circle"
        case .licence: "key"
        }
    }
    var group: SettingsPaneGroup { self == .licence ? .entitlement : .configuration }
    static var defaultPane: Self { .general }
}

enum Support {
    static let app = SupportApp(slug: "cupertino", displayName: "Cupertino", siteURL: …)
    static let settings = SettingsSelection<SettingsPane>(app: app, legacyKeys: ["settingsPane"])
}

SettingsScaffold(selection: Support.settings, staged: DemoSeed.stagedPane) { pane in
    switch pane {
    case .general: GeneralPane()
    case .activity: ActivityPane()
    case .about: AboutSettingsPane(app: Support.app)
    case .licence: LicencePane()
    }
}
.settingsWindowSize(CGSize(width: 720, height: 520))
```

### Deep-linking

Two lines, in this order, and the order is the whole mechanism:

```swift
Support.settings.select(.licence)
openSettings()                       // or the app's own window controller
```

The write moves the sidebar; opening is a separate act. The scaffold binds through
`@AppStorage`, so the write lands whether the window is being built for the first time or has
been open behind Xcode for an hour. Mirroring the value into `@State` is exactly how a deep link
into an *already-open* window stops working — and only for that case, which is the one nobody
tests.

`openSettings` is deliberately not wrapped: it does not exist on iOS, and the two `LSUIElement`
apps open a hand-built `NSWindow` that knows about their dock presence, tabbing mode and
activation policy. The contract stops at the write.

### `legacyKeys` is not optional for three apps

`SettingsSelection(app:)` derives `"<slug>.settingsPane"`. Any app that shipped a bare
`"settingsPane"` must pass `legacyKeys: ["settingsPane"]` or every user's pane silently resets.
The migration runs once, only when the canonical key is empty, and removes the old key.

### Launch at login

macOS only. One `LoginItem` per app beside its `SupportApp`, one call at launch, and the section
as the **first** thing in the General pane:

```swift
enum Support {
    static let loginItem = LoginItem(app: app)       // cupertino: legacyDesiredKeys: ["launchAtLoginDesired"]
}

// applicationDidFinishLaunching, after any screenshot-mode early return
Support.loginItem.healIfNeeded()

Form {
    LaunchAtLoginSection(Support.loginItem, detail: "Starts on demand anyway; this removes the wait.")
    // …the rest of General
}
```

It keeps two facts apart: what the user **asked for** (`<slug>.launchAtLogin`) and what
`SMAppService` **reports**. A registration is a bundle at a path, and a Sparkle update replaces
the bundle — with only the service's answer, the box is quietly unticked after an update and the
app has stopped launching at login. `healIfNeeded()` re-registers once when the two disagree. An
item that was already enabled before the app adopted this is taken as asked for, so existing users
are covered from their next update.

The section draws what the service reports, never the last request. It says when macOS is waiting
on the user's approval, and it refuses to register a translocated copy or one outside an
Applications folder, which would leave a login item pointing at a path that is about to vanish.
Under a screenshot capture pass `service: PinnedLoginItemService()` and an `/Applications`
`bundleURL`, so the golden shows neither the capturing Mac's registration nor the location warning.

### About

```swift
AboutSettingsPane(app: Support.app)              // a whole pane
AboutSettingsSection(app: Support.app)           // just the rows, for an existing Form
```

Version and build from `Diagnostics`, the machine, a copy button that writes
`Diagnostics.bugReportSummary` to the pasteboard, and `SupportSettingsSection` beneath it.

The support rows matter most on an **iPhone**, which has no Help menu for `SupportCommands` to
fill — without them the feedback form, the tracker and the support page are reachable from
nowhere at all. An iPad with a menu bar gets both.

Pass `diagnostics:` to pin the version for a screenshot run. A real version number renders into
every settings capture, which churns a golden gate on each release and can publish a version to
a marketing site before the listing showing it has caught up.

### Screenshots

`staged:` forces a pane **and drops every selection write** while it is set, so a capture run
cannot land on whatever the developer last had open, and cannot change it either. `onPaneChange:`
is there to assert on: a settings window that came up on the wrong pane is a valid,
correctly-sized, perfectly still photograph that every automated gate passes.

The package never learns about `DemoSeed`, `ScreenshotStage` or `DemoMode` — differently named
per-app types with different launch-argument parsing. It takes a pane or nil.

### Sizing

`.settingsWindowSize(_:)` goes on the **content**, never the scene or the window. A `Settings`
scene sizes itself to its content, so `NSWindow.setContentSize` loses to SwiftUI's clamp: it
takes the height and silently drops the width. Three apps in the fleet found that separately
before anyone noticed it was one bug.

## The menu bar panel

The chrome around a `MenuBarExtra` summary — header, footer row, width, scroll cap — once. The
app supplies only the rows in the middle.

```swift
import SupportKitMenuBar

MenuBarExtra {
    MenuBarPanel(
        app: .bastion,
        version: AppInfo.shortVersion,
        onOpenApp: { MainWindowController.show() },
        onShowAbout: { SettingsWindowController.show(.about) },
        footer: MenuBarFooter(
            routes: [
                .logs { MainWindowController.show(.log) },
                .settings { SettingsWindowController.show() },
            ],
            whatsNew: Changelog.hasUnseen
                ? .init(version: AppInfo.version) { SettingsWindowController.show(.whatsNew) }
                : nil
        )
    ) {
        // the app's own rows
    }
} label: { ... }
```

`onShowAbout` is optional: pass nil while an app has no About pane and the version renders as
plain text rather than as a button that goes nowhere.

### The header

Name at the leading edge, version pinned to the trailing edge — armada's arrangement, which is
the one the fleet settled on. Three apps showed a version here and they did not agree: two set
it immediately after the name as a baseline-aligned suffix, one pushed it right. Both sides had
a written reason, but the suffix argument was about a panel too narrow to spend width on, and
the panel is a fixed 320 for everyone now. What settles it is that the two ends of the row are
two destinations — the name opens the app, the version opens About — and a suffix reads as a
footnote to the title rather than as its own target.

### One footer, two idioms

The fleet drew two footers and they looked incompatible — three apps a single row, two a
vertical list. The difference turned out to be that the stacked pair have a **verb** ("Collect
now", "Refresh Now"): work the panel does itself, which is neither the primary nor a route and
cannot be reduced to a glyph nobody has to be taught. Everything else they listed was already a
route. So it is one footer with one optional part:

```
[verbs — stacked, named, only if the app has any]
───────
[Open <App>]  ·······  [route] [route]  [Quit]
[What's new in 1.2.0…  — only just after an update]
```

Two routes is the working ceiling, and it is a measurement rather than a taste: a fourth *text*
button was recorded truncating "Open Cupertino" to "Open Cuperti…" at this width. Glyphs cost a
fraction of that, which is why the row holds two of them and could not hold one more word.

### Sizing

`MenuBarMetrics.default` is 320 / 14 / 12, which is what the fleet converged on without
coordinating. The number and the reasoning that argues for it now live in the same place —
previously these were five sets of inline literals restated in prose more often than in code,
and two comments in one app disagreed about that app's own width.

`bodyCap` is derived from the screen rather than fixed, because a constant tuned on a laptop is
wrong on a studio display in the direction nobody notices until a panel is cut off. It is read
at layout time and is not reactive to a display change; `MenuBarExtra` content is lazy and
rebuilt on every open, so the only window it can be wrong in is a display change *while the
panel is open*.

## Toolbar caption controls

A toolbar control that names a setting over its value — "Model" above "Parakeet TDT v3" — with a
glyph beside it, opening a popover or a menu.

```swift
import SupportKitToolbar

.toolbar {
    ToolbarCaptionItem(placement: .primaryAction) {
        ToolbarCaptionButton(
            "Model",
            value: engine.current?.displayName,
            placeholder: "Choose a model",
            systemImage: "cube.box",
            isPresented: $isPickerPresented
        ) {
            ModelPicker()
        }
        .help("Choose the model the next transcription uses")
    }
}
```

`ToolbarCaptionMenu` draws the same label over menu items instead of a popover. Reach for the
popover when a row needs more than a name — a summary, a download size, or a slider, which a menu
dismisses on the first drag.

### Why it exists

Five controls in three apps drew this label by hand. Cadence's broke on macOS 27, and the other
four are built the same way. The toolbar there wraps each item in a glass capsule one control row
tall and clips what does not fit, so the value lost its lower half and its last characters. The
binary was built against the 26.5 SDK and drew correctly on 26: the toolbar changed underneath it,
nothing was relinked.

The controls draw their own capsule, and `ToolbarCaptionItem` hides the toolbar's shared
background with `sharedBackgroundVisibility(.hidden)`. That modifier belongs to the toolbar item,
not the view inside it, so no control can apply it to itself. The wrapper is how a call site
cannot forget it — and a call site that forgot would look right on 26 and ship clipped on 27.

### Menus

Contour's toolbar menus hold a single `Text` with a newline in an `AttributedString`, on the
grounds that a toolbar `Menu` flattened a stacked label to its first `Text`. On macOS 27 it is
that workaround that flattens: it draws the caption and an ellipsis. A button-styled menu drawing
its own glass keeps the stacked label whole, and that is what `ToolbarCaptionMenu` is.

### Dimming

A plain button style leaves a custom label bright in an inactive window while the system items
beside it dim. The label steps its text down a level when its window is inactive or the control is
disabled, so it dims with its neighbours.

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

The toolbar caption controls are the exception, on purpose. Their glass is not a look laid over a
bare control: it is the capsule the toolbar would have drawn, replaced because the toolbar's own
clips a two-line label on macOS 27. Drawn bare, a caption control would be a label with no
control around it. See [Toolbar caption controls](#toolbar-caption-controls).

## Localization

The package ships its own strings in English and French, one String Catalog per UI target.
Which language shows follows **the app's** language, not the Mac's: an English-only app on a
French Mac stays English throughout, and a bilingual app gets French rows beside its own French
screens.

Two kinds of text, two catalogs:

- **What the package names** — "Send Feedback…", "Version", "Quit" — lives in the package's
  catalog and is looked up with `bundle: .module`. The app has nothing to add.
- **What the app names** — pane titles, `intro:`, `debugNotice:`, a menu bar verb — is a
  `LocalizedStringKey`, resolved in the app's catalog like any other string the app writes.

Every lookup goes through `localized(_:)` rather than a bare `Text("…")`, because a literal inside
a package resolves against `Bundle.main` and silently draws English. That hides the literal from
Xcode's extractor, so `SupportKitLocalizationTests` does the extractor's job: every call site has
an entry, every entry has a call site, French is complete, no literal reaches SwiftUI unwrapped,
and no entry generates a Swift symbol. That last one is not tidiness — Xcode 26 turns "Send
Feedback" and "Send Feedback…" into the same symbol, which breaks the build of every app linking
the module while `swift build` stays green.

Adding a string means adding its French in the same commit.

## Requirements

macOS 26+ / iOS 26+, Swift 6. The floor follows the consuming apps, every one of which is on 26.
It was macOS 15 / iOS 17 until 1.6.0, on the reasoning that nothing here needed more — which
stopped being true when `SupportKitMenuBar` arrived and leaned on the macOS 26 glass button
styles.

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
