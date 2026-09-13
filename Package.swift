// swift-tools-version: 6.0
import PackageDescription

// Three products, deliberately split.
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
let package = Package(
  name: "swift-support-kit",
  platforms: [.macOS("26.0"), .iOS("26.0")],
  products: [
    .library(name: "SupportKit", targets: ["SupportKit"]),
    .library(name: "SupportKitUI", targets: ["SupportKitUI"]),
    .library(name: "SupportKitSettings", targets: ["SupportKitSettings"]),
    .library(name: "SupportKitMenuBar", targets: ["SupportKitMenuBar"]),
  ],
  targets: [
    .target(name: "SupportKit"),
    .target(name: "SupportKitUI", dependencies: ["SupportKit"]),
    .target(name: "SupportKitSettings", dependencies: ["SupportKit", "SupportKitUI"]),
    .target(name: "SupportKitMenuBar", dependencies: ["SupportKit"]),
    .testTarget(name: "SupportKitTests", dependencies: ["SupportKit"]),
    .testTarget(name: "SupportKitSettingsTests", dependencies: ["SupportKitSettings"]),
    .testTarget(name: "SupportKitMenuBarTests", dependencies: ["SupportKitMenuBar"]),
  ]
)
