#if os(macOS)
  import AppKit
  import SwiftUI

  /// Turns off the two highlights the sidebar's table draws on its own, so the rows can draw
  /// their own instead. Put it behind the `List`: `.background(SidebarTableFeedback())`.
  ///
  /// Its selection is a solid accent slab with white text, which outweighed everything else in
  /// the sidebar: a selected row draws `sidebarSelection` instead. Its drop feedback draws the
  /// row under a drag exactly like a selection, which says something false when the outline of
  /// a whole section (`sectionDropTarget`) or of one row (`sidebarDropOutline`) already says
  /// where the drag will land.
  ///
  /// SwiftUI has no say in either, so this finds the `NSTableView` behind the `List` it is put
  /// behind and sets them there.
  public struct SidebarTableFeedback: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> NSView {
      let view = NSView(frame: .zero)
      // Not yet in the hierarchy; one runloop hop later it is.
      DispatchQueue.main.async { Self.apply(from: view) }
      return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
      Self.apply(from: nsView)
    }

    /// The nearest table: up from this view, one level at a time, so another table elsewhere in
    /// the window is never the one found.
    private static func apply(from view: NSView) {
      var ancestor = view.superview
      while let current = ancestor {
        if let table = firstTable(in: current) {
          if table.draggingDestinationFeedbackStyle != .none {
            table.draggingDestinationFeedbackStyle = .none
          }
          if table.selectionHighlightStyle != .none {
            table.selectionHighlightStyle = .none
          }
          return
        }
        ancestor = current.superview
      }
    }

    private static func firstTable(in view: NSView) -> NSTableView? {
      if let table = view as? NSTableView { return table }
      for subview in view.subviews {
        if let table = firstTable(in: subview) { return table }
      }
      return nil
    }
  }
#endif
