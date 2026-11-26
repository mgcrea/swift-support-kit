import Observation

#if os(macOS)
  import AppKit
#endif

/// Which target a drag in progress would land in: a section of a grouped list, so the whole
/// section can light up rather than the one row under the pointer, or a single sidebar row.
///
/// Every row and header of a section is a drop target of its own, and a drag moving from one
/// to the next can hear that it entered the next before it hears that it left the last. So
/// each target counts the reports it has had, and the one entered last wins.
///
/// Cadence's, Valise's and Carbone's sidebars each carried a copy until 1.30.0, and the fixes
/// below reached them one at a time.
public struct DropTargeting<ID: Hashable>: Equatable {
  /// What the drag started in. A drop there changes nothing, so it never lights.
  public var source: ID?
  private var counts: [ID: Int] = [:]
  private var latest: ID?

  public init(source: ID? = nil) {
    self.source = source
  }

  /// One target of `id` reports the drag entering it, or leaving it. An exit with no entry
  /// before it (a drag that began over a target) is forgotten, so no count goes negative and
  /// keeps the target dark on the next pass.
  public mutating func target(_ id: ID, isTargeted: Bool) {
    let count = (counts[id] ?? 0) + (isTargeted ? 1 : -1)
    counts[id] = count > 0 ? count : nil
    if isTargeted { latest = id }
  }

  /// What to light, if the drag is over something it can land in. Late news that the drag
  /// left the target it is now over does not darken it, and leaving the newer one falls back
  /// to one still held.
  public var lit: ID? {
    if let latest, counts[latest] != nil {
      return latest == source ? nil : latest
    }
    return counts.keys.first { $0 != source }
  }
}

extension DropTargeting: Sendable where ID: Sendable {}

/// The `DropTargeting` of the drag in progress, shared through the environment by the rows and
/// headers that report it and the ones that draw it. A list owns one, as `@State`, and puts it
/// in the environment with `.environment(highlight)`; `sectionDropTarget` and
/// `sectionDragSource` read it there by its `ID`.
///
/// What is lit lights at once and goes dark a moment late: the Mac sidebar says a drag left a
/// row before it says the drag entered the next, and an outline that went dark in between
/// would blink at every row.
@MainActor
@Observable
public final class DropHighlight<ID: Hashable> {
  public private(set) var lit: ID?

  @ObservationIgnored private var targeting = DropTargeting<ID>()
  @ObservationIgnored private var darkening: Task<Void, Never>?
  @ObservationIgnored private var release: Task<Void, Never>?
  @ObservationIgnored private let buttonIsDown: (() -> Bool)?

  /// `buttonIsDown` says whether the drag can still be going; nil leaves the end to the
  /// targets and the drag session, as on iOS. Tests hand in their own.
  public init(buttonIsDown: (() -> Bool)? = DropHighlight.primaryButtonIsDown) {
    self.buttonIsDown = buttonIsDown
  }

  /// On the Mac, whether the primary mouse button is down; nil elsewhere.
  public nonisolated static var primaryButtonIsDown: (() -> Bool)? {
    #if os(macOS)
      { NSEvent.pressedMouseButtons & 1 != 0 }
    #else
      nil
    #endif
  }

  /// A row in `id` started a drag. Called on every update of it, so setting the same source
  /// again changes nothing. A list whose drags never come from its own targets (a document
  /// list dragged onto sidebar rows) never calls it.
  public func dragBegan(in id: ID) {
    watchForRelease()
    guard targeting.source != id else { return }
    targeting = DropTargeting(source: id)
    show()
  }

  /// A target of `id` hears the drag enter it, or leave it.
  public func target(_ id: ID, isTargeted: Bool) {
    if isTargeted { watchForRelease() }
    targeting.target(id, isTargeted: isTargeted)
    show()
  }

  /// Dropped, or let go of somewhere else: nothing is lit any more.
  public func dragEnded() {
    targeting = DropTargeting()
    darkening?.cancel()
    darkening = nil
    release?.cancel()
    release = nil
    lit = nil
  }

  private func show() {
    let next = targeting.lit
    darkening?.cancel()
    darkening = nil
    guard next == nil, lit != nil else {
      if lit != next { lit = next }
      return
    }
    darkening = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(80))
      guard !Task.isCancelled, let self else { return }
      lit = targeting.lit
    }
  }

  /// The Mac sidebar reports no drag session, and a drag let go outside every target need not
  /// hear that it left the last one. So on the Mac the drag is over when the button comes up,
  /// whatever the targets last said.
  private func watchForRelease() {
    guard let buttonIsDown, release == nil else { return }
    release = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(150))
        guard !buttonIsDown() else { continue }
        self?.dragEnded()
        return
      }
    }
  }
}
