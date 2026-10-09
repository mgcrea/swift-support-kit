import SwiftUI

/// The sheet raised where a Pro feature was asked for: what was reached for, what stays free,
/// what Pro adds, and Unlock.
///
/// Calque's and Filiation's layout, the newest in the fleet and the only ones laid out for an
/// iPhone. It says what stays free before any price, because a sheet that opens on a price
/// reads as if everything is locked. Its rows are the `ProFeatureEntry` list the app also
/// gives `ProSettingsPane`, as Pochette and Cadence do, so the sheet and Settings cannot
/// advertise different things. With no product it shows a disabled Unavailable rather than an
/// Unlock that fails, as Pochette and Cadence do. It closes by itself once the purchase goes
/// through; `proUpgradeSheet(item:isUnlocked:onUnlock:content:)` then finishes what was asked.
///
/// Takes values and closures, never a store, like `ProSettingsPane`.
public struct ProUpgradeSheet: View {
  /// What the Unlock position holds.
  public enum Action: Equatable {
    /// A purchase or restore is in flight, or the store has not answered yet.
    case working
    case buy(price: String)
    /// The product did not load: offline, or not yet in App Store Connect.
    case unavailable
    case owned
  }

  /// `nonisolated` so tests and callers off the main actor can ask without hopping to it.
  public nonisolated static func action(state: ProPurchaseState, isWorking: Bool) -> Action {
    if isWorking { return .working }
    switch state {
    case .unknown: return .working
    case .locked(let price?): return .buy(price: price)
    case .locked(nil): return .unavailable
    case .unlocked: return .owned
    }
  }

  private let productName: LocalizedStringKey
  private let headline: LocalizedStringKey?
  private let alwaysFree: LocalizedStringKey
  private let features: [ProFeatureEntry]
  private let state: ProPurchaseState
  private let isWorking: Bool
  private let errorMessage: String?
  private let installedVersion: String
  private let purchase: () -> Void
  private let restore: () -> Void

  @Environment(\.dismiss) private var dismiss

  /// - Parameters:
  ///   - productName: "Pupitre Pro", in the app's catalog: the headline when `headline` is nil.
  ///   - headline: what was reached for, in the app's catalog: "The Concert Grand Is in
  ///     Pupitre Pro".
  ///   - alwaysFree: what stays free, in the app's catalog, drawn under the headline.
  ///   - features: the same entries the app passes `ProSettingsPane`.
  ///   - errorMessage: the store's last error, already worded by the app.
  ///   - purchase: buys. The sheet never calls StoreKit itself.
  public init(
    productName: LocalizedStringKey,
    headline: LocalizedStringKey?,
    alwaysFree: LocalizedStringKey,
    features: [ProFeatureEntry],
    state: ProPurchaseState,
    isWorking: Bool = false,
    errorMessage: String? = nil,
    installedVersion: String = ReleaseNotes.bundleVersion,
    purchase: @escaping () -> Void,
    restore: @escaping () -> Void
  ) {
    self.productName = productName
    self.headline = headline
    self.alwaysFree = alwaysFree
    self.features = features
    self.state = state
    self.isWorking = isWorking
    self.errorMessage = errorMessage
    self.installedVersion = installedVersion
    self.purchase = purchase
    self.restore = restore
  }

  public var body: some View {
    #if os(macOS)
      content.frame(width: 460)
    #else
      // The width of the screen on an iPhone, where 460 points run off both edges: scrolled,
      // for a large text size, and started at the top.
      ScrollView { content }
    #endif
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: 16) {
      header
      Divider()
      VStack(alignment: .leading, spacing: 10) {
        ForEach(ProFeatureEntry.ordered(features, installedVersion: installedVersion)) {
          feature in
          ProFeatureRow(
            feature: feature, isNew: feature.isNew(installedVersion: installedVersion),
            isUnlocked: false)
        }
      }
      if let errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      }
      Divider()
      footer
    }
    .padding(24)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("pro.upgrade")
    // Closed on success rather than left selling something the user now owns.
    .onChange(of: state) { _, new in if new == .unlocked { dismiss() } }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: "sparkles")
        .font(.system(size: 34))
        .foregroundStyle(.tint)
      VStack(alignment: .leading, spacing: 4) {
        Text(headline ?? productName)
          .font(.title2.weight(.semibold))
          .fixedSize(horizontal: false, vertical: true)
        Text(alwaysFree)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var footer: some View {
    VStack(alignment: .leading, spacing: 10) {
      #if os(macOS)
        HStack {
          restoreButton
          Spacer()
          notNowButton
          unlockButton
        }
      #else
        // Three in a row are wider than an iPhone: the purchase the width of the sheet, as an
        // iPhone app puts its main action, and the other two under it.
        unlockButton
          .controlSize(.large)
        HStack {
          restoreButton
          Spacer()
          notNowButton
        }
      #endif
      Text(
        localized(
          "Bought once: no subscription, no paid upgrades. Shared with your family through Family Sharing, and on every device signed in to your Apple Account."
        )
      )
      .font(.caption)
      .foregroundStyle(.tertiary)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  /// Also App Review's requirement on iPhone and iPad, where Settings may never be opened.
  private var restoreButton: some View {
    Button(localized("Restore Purchase"), action: restore)
      .buttonStyle(.borderless)
      .disabled(isWorking)
  }

  private var notNowButton: some View {
    Button(localized("Not Now")) { dismiss() }
      .keyboardShortcut(.cancelAction)
  }

  @ViewBuilder private var unlockButton: some View {
    switch Self.action(state: state, isWorking: isWorking) {
    case .working:
      ProgressView().controlSize(.small)
    case .buy(let price):
      Button(action: purchase) {
        Text(localized("Unlock for \(price)"))
          .fontWeight(.semibold)
          #if os(iOS)
            .frame(maxWidth: .infinity)
          #endif
      }
      .buttonStyle(.borderedProminent)
      .keyboardShortcut(.defaultAction)
    case .unavailable:
      Button(localized("Unavailable")) {}
        .disabled(true)
        .help(localized("The App Store could not be reached."))
    case .owned:
      EmptyView()
    }
  }
}

// Titles are built by hand because a bare literal here would read as unlocalized to the catalog scan.
#Preview("Locked") {
  ProUpgradeSheet(
    productName: "Pupitre Pro", headline: "The Concert Grand Is in Pupitre Pro",
    alwaysFree: "Level 1 of every tune, and your own MIDI files, are free.",
    features: [
      ProFeatureEntry(
        id: "grand", title: LocalizedStringResource(stringLiteral: "The Concert Grand"),
        systemImage: "pianokeys"),
      ProFeatureEntry(
        id: "library", title: LocalizedStringResource(stringLiteral: "Every level and every piece"),
        systemImage: "books.vertical"),
    ],
    state: .locked(price: "$9.99"), purchase: {}, restore: {})
}

#Preview("Unavailable") {
  ProUpgradeSheet(
    productName: "Pupitre Pro", headline: nil, alwaysFree: "Level 1 is free.",
    features: [
      ProFeatureEntry(
        id: "grand", title: LocalizedStringResource(stringLiteral: "The Concert Grand"),
        systemImage: "pianokeys")
    ],
    state: .locked(price: nil), purchase: {}, restore: {})
}
