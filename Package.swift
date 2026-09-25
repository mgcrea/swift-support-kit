// swift-tools-version: 6.0
import PackageDescription

// Six products, deliberately split.
//
// `SupportKit` is Foundation-only, so it can be unit-tested without a host app
// and imported from a non-UI module. `SupportKitUI` is the SwiftUI surface. An
// app that only wants the URL builder does not pull SwiftUI in to get it.
//
// `SupportKitSettings` is the settings scaffold, and it is a third product for
// the same reason the first two are split rather than one. `SupportKitUI` is a
// hundred and thirty lines that nine shipping apps already link and that has no
// reason to change again; the scaffold is where twelve apps' disagreements about
// their settings pane will land, and it will churn. Keeping them apart means a
// minor bump for a sidebar metric does not re-review the Help menu.
//
// `SupportKitMenuBar` and `SupportKitToolbar` are macOS-only chrome that only
// some apps draw. The toolbar module is also the one place the package imposes
// glass, for the reason documented on `ToolbarCaptionLabel`, and an app that
// links the Help menu should inherit neither.
//
// `SupportKitMemory` is the memory budget for apps that run on-device inference,
// and it depends on nothing — not even on MLX, which is what it was written for.
// Every app that links the Help menu would otherwise fetch mlx-swift to get it;
// the app hands the two numbers to MLX itself, in three lines. It is also the
// only product with no UI at all, which is why it is not folded into
// `SupportKit`: an app that wants the budget has no use for the support URLs.
//
// The platform floor follows the consuming apps, which are now all on macOS 26
// and iOS 26 — checked target by target, including Cupertino's bridge helper at
// macOS 14, which links no package product and so does not hold the floor down.
//
// It was macOS 15 / iOS 17 on the reasoning that nothing here needs more, which
// was true of SupportKit and SupportKitUI and stopped being true when
// SupportKitMenuBar arrived: `.buttonStyle(.glass)` is a macOS 26 API, and a
// declared floor of 15 meant CI built the package on a runner whose toolchain
// could not compile it. That job had been failing since 1.2.0 — three releases
// during which the package's own tests never ran on either runner.
//
// Raising the floor is the honest fix rather than availability-guarding the
// call: no consumer is below 26, so a guard would be dead code protecting
// nobody.
//
// `defaultLocalization` is what gives `Bundle.module` a localization table at
// all, and it names the language the source is written in. Each of the three UI
// targets owns a `Resources/Localizable.xcstrings`, because a bare `Text("…")`
// inside a package resolves against `Bundle.main` — the host app's bundle — finds
// no entry there, and draws the English key to a French user with no build error
// and no crash. Two apps in the fleet are bilingual, and that is the reason one
// of them rebuilt the Help menu and the support rows by hand rather than link
// them. Every string these targets draw goes through `localized(_:)`, which names
// `.module`, and `SupportKitLocalizationTests` holds the catalogs to the call
// sites.
//
// `SupportKit` has no catalog on purpose. Its English — the issue template, the
// clipboard summary, the mail body — is read by the maintainer, not shown in the
// app.
let package = Package(
  name: "swift-support-kit",
  defaultLocalization: "en",
  platforms: [.macOS("26.0"), .iOS("26.0")],
  products: [
    .library(name: "SupportKit", targets: ["SupportKit"]),
    .library(name: "SupportKitUI", targets: ["SupportKitUI"]),
    .library(name: "SupportKitSettings", targets: ["SupportKitSettings"]),
    .library(name: "SupportKitMenuBar", targets: ["SupportKitMenuBar"]),
    .library(name: "SupportKitToolbar", targets: ["SupportKitToolbar"]),
    .library(name: "SupportKitMemory", targets: ["SupportKitMemory"]),
  ],
  targets: [
    .target(name: "SupportKit"),
    .target(
      name: "SupportKitUI",
      dependencies: ["SupportKit"],
      resources: [.process("Resources")]
    ),
    .target(
      name: "SupportKitSettings",
      dependencies: ["SupportKit", "SupportKitUI"],
      resources: [.process("Resources")]
    ),
    .target(
      name: "SupportKitMenuBar",
      dependencies: ["SupportKit"],
      resources: [.process("Resources")]
    ),
    // No catalog: every word it draws is the app's, handed over as a key or as
    // data, so there is nothing for `SupportKitLocalizationTests` to hold.
    .target(name: "SupportKitToolbar"),
    // No catalog: it draws nothing.
    .target(name: "SupportKitMemory"),
    .testTarget(name: "SupportKitTests", dependencies: ["SupportKit"]),
    .testTarget(name: "SupportKitSettingsTests", dependencies: ["SupportKitSettings"]),
    .testTarget(name: "SupportKitMenuBarTests", dependencies: ["SupportKitMenuBar"]),
    .testTarget(name: "SupportKitToolbarTests", dependencies: ["SupportKitToolbar"]),
    .testTarget(name: "SupportKitMemoryTests", dependencies: ["SupportKitMemory"]),
    // Depends on no module: it reads the sources and the catalogs off disk, so a
    // lookup that happens to resolve at runtime for the wrong reason cannot fool it.
    .testTarget(name: "SupportKitLocalizationTests"),
  ]
)
