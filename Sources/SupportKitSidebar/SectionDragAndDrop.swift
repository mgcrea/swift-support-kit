import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// What a row dragged within one app carries: an id, and nothing else. The app declares
/// `contentType`, exported by its Info.plist and conforming to `public.data` only, so another
/// app the drag reaches finds nothing it can read as text, a URL or a file; and the payload
/// goes only to this process, since apps such as Files would otherwise take a `public.data`
/// item as a file of JSON.
///
/// ```swift
/// extension UTType {
///   nonisolated static let cadenceRecording = UTType(
///     exportedAs: "io.mgcrea.cadence.recording", conformingTo: .data)
/// }
///
/// nonisolated struct RecordingReference: InternalDragReference {
///   static var contentType: UTType { .cadenceRecording }
///   let id: UUID
/// }
/// ```
public protocol InternalDragReference: Codable, Transferable, Sendable {
  /// The app's own exported type for this payload.
  static var contentType: UTType { get }
}

extension InternalDragReference {
  public static var transferRepresentation: some TransferRepresentation {
    CodableRepresentation(for: Self.self, contentType: contentType)
      .visibility(.ownProcess)
  }
}

extension View {
  /// Makes this row or header somewhere to drop `Item`s, into the section `id`. While a drag
  /// is over any target of the section, the whole section is outlined in `tint`, through the
  /// environment's `DropHighlight<ID>`: each target draws its own stretch of that one outline,
  /// `outline`, and nil draws none. `action` is handed what was dropped, and answers whether it
  /// took it.
  ///
  /// Accepts `Item` only, so anything else (files dragged in from the Finder, when `Item` is
  /// an app's own reference) passes through to a drop further out.
  public func sectionDropTarget<ID: Hashable, Item: Transferable>(
    _ id: ID, accepting item: Item.Type, tint: Color, outline: SectionOutline?,
    isHeader: Bool = false, action: @escaping ([Item]) -> Bool
  ) -> some View {
    modifier(
      SectionDropTarget(
        id: id, tint: tint, outline: outline, isHeader: isHeader, action: action))
  }

  /// Makes this row draggable as `payload`, and tells the environment's `DropHighlight<ID>`
  /// the drag started in `id`, so that section stays unlit: a drop there would change
  /// nothing. Nothing when `isEnabled` is false: a row that cannot move is not picked up.
  public func sectionDragSource<ID: Hashable, Payload: Transferable>(
    in id: ID, isEnabled: Bool = true, payload: @escaping () -> Payload
  ) -> some View {
    modifier(SectionDragSource(id: id, isEnabled: isEnabled, payload: payload))
  }
}

private struct SectionDropTarget<ID: Hashable, Item: Transferable>: ViewModifier {
  @Environment(DropHighlight<ID>.self) private var highlight: DropHighlight<ID>?

  let id: ID
  let tint: Color
  let outline: SectionOutline?
  let isHeader: Bool
  let action: ([Item]) -> Bool

  func body(content: Content) -> some View {
    content
      .sectionDropOutline(outline, isLit: highlight?.lit == id, tint: tint, isHeader: isHeader)
      .dropDestination(for: Item.self) { items, _ in
        highlight?.dragEnded()
        return action(items)
      } isTargeted: { isTargeted in
        highlight?.target(id, isTargeted: isTargeted)
      }
  }
}

private struct SectionDragSource<ID: Hashable, Payload: Transferable>: ViewModifier {
  @Environment(DropHighlight<ID>.self) private var highlight: DropHighlight<ID>?

  let id: ID
  let isEnabled: Bool
  let payload: () -> Payload

  @ViewBuilder
  func body(content: Content) -> some View {
    if isEnabled {
      let draggable = content.draggable(begin())
      // The payload is what names the source on the Mac, whose sidebar rows never report a
      // drag session. Where the session is reported, it also darkens everything once the drag
      // ends; elsewhere leaving, dropping and letting go do that through the targets.
      if #available(iOS 27, *) {
        draggable.onDragSessionUpdated { session in
          switch session.phase {
          case .initial, .active: highlight?.dragBegan(in: id)
          case .ended, .dataTransferCompleted: highlight?.dragEnded()
          default: break
          }
        }
      } else {
        draggable
      }
    } else {
      content
    }
  }

  /// Asked for once, as the drag begins, so it is also where the drag is seen to begin.
  private func begin() -> Payload {
    highlight?.dragBegan(in: id)
    return payload()
  }
}
