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
// The platform floor is macOS 15 / iOS 17 because nothing here needs more —
// this package builds URLs, reads two sysctls, and touches UserDefaults. The
// consuming apps sit anywhere from macOS 15.5 to 26.x, and a floor raised to
// match the newest of them would lock out the oldest for no gain.
let package = Package(
  name: "swift-support-kit",
  platforms: [.macOS(.v15), .iOS(.v17)],
  products: [
    .library(name: "SupportKit", targets: ["SupportKit"]),
    .library(name: "SupportKitUI", targets: ["SupportKitUI"]),
    .library(name: "SupportKitSettings", targets: ["SupportKitSettings"]),
  ],
  targets: [
    .target(name: "SupportKit"),
    .target(name: "SupportKitUI", dependencies: ["SupportKit"]),
    .target(name: "SupportKitSettings", dependencies: ["SupportKit", "SupportKitUI"]),
    .testTarget(name: "SupportKitTests", dependencies: ["SupportKit"]),
    .testTarget(name: "SupportKitSettingsTests", dependencies: ["SupportKitSettings"]),
  ]
)
