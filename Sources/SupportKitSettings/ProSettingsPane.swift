import SupportKit
import SwiftUI

/// One thing Pro unlocks, as the Pro pane lists it.
///
/// Not called `ProFeature` because balise and cadence already have an enum by
/// that name, and it is the right name there: theirs decides what is gated. This
/// only describes a row. The intended shape is one `entry` property on the app's
/// own enum, so the gate, the paywall and this list are read from one place and
/// a feature cannot ship in one of them and be missing from the others.
public struct ProFeatureEntry: Identifiable, Sendable {
  public let id: String
  /// In the **app's** catalog: `LocalizedStringResource` defaults to
  /// `Bundle.main`, which is the host app when the value is built there.
  public let title: LocalizedStringResource
  public let summary: LocalizedStringResource?
  public let systemImage: String
  /// The app version this feature joined Pro in, three-part like
  /// `MARKETING_VERSION`. Nil for anything that has been there since Pro
  /// launched, which never draws as new.
  public let since: String?

  public init(
    id: String,
    title: LocalizedStringResource,
    summary: LocalizedStringResource? = nil,
    systemImage: String,
    since: String? = nil
  ) {
    self.id = id
    self.title = title
    self.summary = summary
    self.systemImage = systemImage
    self.since = since
  }

  /// Whether the row wears a "New" badge in the build that is running.
  ///
  /// New for the whole minor it arrived in, so a feature from 1.4.0 is still
  /// new in 1.4.2 and stops being new at 1.5.0. Tied to the version rather than
  /// to what this user has already looked at, which needs no defaults key: the
  /// badge answers "what did this release add", the same question for everyone,
  /// and it clears by itself on the next minor rather than waiting for a visit
  /// that may never happen.
  public func isNew(installedVersion: String = ReleaseNotes.bundleVersion) -> Bool {
    guard let since else { return false }
    return Self.minor(since) == Self.minor(installedVersion)
  }

  /// The list as the pane draws it: this minor's additions first, then the rest
  /// in the order the app gave. Stable, so the app's order still means something.
  public static func ordered(
    _ entries: [ProFeatureEntry], installedVersion: String = ReleaseNotes.bundleVersion
  ) -> [ProFeatureEntry] {
    entries.filter { $0.isNew(installedVersion: installedVersion) }
      + entries.filter { !$0.isNew(installedVersion: installedVersion) }
  }

  private static func minor(_ version: String) -> [Int] {
    let parts = version.split(separator: ".").map { Int($0) ?? 0 }
    return [parts.first ?? 0, parts.count > 1 ? parts[1] : 0]
  }
}

/// Where the purchase stands, as far as the pane needs to know.
///
/// Three cases rather than a `Bool`, for the reason balise's `ProStatus` gives:
/// at launch the answer is not known yet, and drawing a Buy button during that
/// window offers Pro to somebody who has already paid.
public enum ProPurchaseState: Sendable, Equatable {
  case unknown
  /// `price` is the store's display price. Nil means the product did not load,
  /// which the pane says, rather than drawing a Buy button with no price on it.
  case locked(price: String?)
  case unlocked
}

/// The features Pro covers, as a `Section` for a `Form` the app already has.
/// What `ProSettingsPane` draws, and what a licence-key pane (bastion,
/// cupertino) can embed without taking the StoreKit wording with it.
///
/// Drawn in both states on purpose. Before the purchase it is the pitch; after
/// it, it is the receipt, and the one place a buyer finds what a later release
/// added to what they already own. A pane that shrinks to "thank you" once
/// unlocked hides exactly the news its most loyal users would want.
public struct ProFeaturesSection: View {
  private let features: [ProFeatureEntry]
  private let isUnlocked: Bool
  private let installedVersion: String

  public init(
    features: [ProFeatureEntry],
    isUnlocked: Bool,
    installedVersion: String = ReleaseNotes.bundleVersion
  ) {
    self.features = features
    self.isUnlocked = isUnlocked
    self.installedVersion = installedVersion
  }

  public var body: some View {
    Section {
      ForEach(ProFeatureEntry.ordered(features, installedVersion: installedVersion)) { feature in
        ProFeatureRow(
          feature: feature,
          isNew: feature.isNew(installedVersion: installedVersion),
          isUnlocked: isUnlocked)
      }
    } header: {
      Text(isUnlocked ? localized("Included with your purchase") : localized("What Pro unlocks"))
    }
  }
}

/// Settings ▸ Pro for an app sold through StoreKit: where the purchase stands,
/// what it covers, and Buy / Restore. What a pane enum's `.pro` case returns.
///
/// Not a paywall. The paywall interrupts at a locked feature and names it; this
/// is where somebody comes to check what they own, or to restore, with nothing
/// blocking them. It takes values and closures rather than a store, because
/// every app's store is different (`ProStore`, `PurchaseManager`,
/// `EntitlementStore`) and none of them belongs in this package.
public struct ProSettingsPane: View {
  private let app: SupportApp
  private let productName: LocalizedStringKey
  private let state: ProPurchaseState
  private let features: [ProFeatureEntry]
  private let alwaysFree: LocalizedStringKey?
  private let isWorking: Bool
  private let errorMessage: String?
  private let installedVersion: String
  private let purchase: () -> Void
  private let restore: () -> Void

  /// - Parameters:
  ///   - productName: "Contour Pro", in the app's catalog.
  ///   - alwaysFree: a sentence on what stays free, drawn under the list. Worth
  ///     passing: a pitch that says only what is locked reads as if everything is.
  ///   - isWorking: a purchase or restore is in flight; both buttons disable.
  ///   - errorMessage: the store's last error, already worded by the app.
  ///   - purchase: buy, or open the app's upgrade sheet. The pane never calls
  ///     StoreKit itself.
  public init(
    app: SupportApp,
    productName: LocalizedStringKey,
    state: ProPurchaseState,
    features: [ProFeatureEntry],
    alwaysFree: LocalizedStringKey? = nil,
    isWorking: Bool = false,
    errorMessage: String? = nil,
    installedVersion: String = ReleaseNotes.bundleVersion,
    purchase: @escaping () -> Void,
    restore: @escaping () -> Void
  ) {
    self.app = app
    self.productName = productName
    self.state = state
    self.features = features
    self.alwaysFree = alwaysFree
    self.isWorking = isWorking
    self.errorMessage = errorMessage
    self.installedVersion = installedVersion
    self.purchase = purchase
    self.restore = restore
  }

  private var isUnlocked: Bool { state == .unlocked }

  public var body: some View {
    Form {
      // The actions sit in the first section, beside the status they change,
      // rather than under the list. Under it they fell below the window in the
      // first app that adopted the pane (KVExplorer's settings window, at 450
      // points, hid Buy and Restore until you scrolled), and a height that
      // shows them depends on how many features and how long an "Always free"
      // each app passes. At the top they are visible at any window height and
      // are the first thing in an iPhone sheet.
      Section {
        HStack(alignment: .center, spacing: 12) {
          Label {
            VStack(alignment: .leading, spacing: 2) {
              Text(productName).font(.body.weight(.semibold))
              Text(statusDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          } icon: {
            Image(systemName: isUnlocked ? "checkmark.seal.fill" : "sparkles")
              .foregroundStyle(isUnlocked ? AnyShapeStyle(.green) : AnyShapeStyle(.tint))
          }
          Spacer(minLength: 0)
          if isWorking { ProgressView().controlSize(.small) }
          actionButton
        }
        if let errorMessage {
          Text(errorMessage)
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
        }
        // Restore is drawn in every state. App Review requires it for a
        // non-consumable, and hiding it once unlocked hides it from the one
        // person who needs it: somebody whose entitlement failed to load.
        Button(localized("Restore Purchase"), action: restore)
          .disabled(isWorking)
      }

      ProFeaturesSection(
        features: features, isUnlocked: isUnlocked, installedVersion: installedVersion)

      if let alwaysFree {
        Section(localized("Always free")) {
          Text(alwaysFree)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .formStyle(.grouped)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("settings.pro.content")
  }

  @ViewBuilder private var actionButton: some View {
    switch state {
    case .unknown:
      EmptyView()
    case .unlocked:
      Label(localized("Purchased"), systemImage: "checkmark")
        .foregroundStyle(.secondary)
        .font(.callout)
    case .locked(let price?):
      Button(localized("Buy for \(price)"), action: purchase)
        .buttonStyle(.borderedProminent)
        .disabled(isWorking)
    case .locked(nil):
      Button(localized("Unavailable")) {}
        .disabled(true)
        .help(localized("The App Store could not be reached."))
    }
  }

  private var statusDetail: String {
    switch state {
    case .unknown: localized("Checking your purchase…")
    case .unlocked:
      localized("Everything is unlocked. Thank you for supporting \(app.displayName).")
    case .locked: localized("A one-time purchase. No subscription.")
    }
  }
}

private struct ProFeatureRow: View {
  let feature: ProFeatureEntry
  let isNew: Bool
  let isUnlocked: Bool

  var body: some View {
    Label {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(feature.title)
          if isNew {
            Text(localized("New"))
              .font(.caption2)
              .padding(.horizontal, 6).padding(.vertical, 1)
              .background(Color.accentColor.opacity(0.15), in: Capsule())
              .foregroundStyle(Color.accentColor)
          }
        }
        if let summary = feature.summary {
          Text(summary)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    } icon: {
      Image(systemName: feature.systemImage)
        .foregroundStyle(.tint)
    }
    // Unlocked, the row says it is yours without a second column of ticks.
    .accessibilityValue(isUnlocked ? Text(localized("Included")) : Text(verbatim: ""))
  }
}
