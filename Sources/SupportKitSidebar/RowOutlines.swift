#if os(macOS)
  import SwiftUI

  extension View {
    /// A selected sidebar row's highlight, in place of the table's (turned off by
    /// `SidebarTableFeedback`): an accent border over a faint wash of it, greyed in a window in
    /// the background as the table's own is. It is the section outline's look, drawn over the
    /// same span, so a selected row and a lit section line up at both edges.
    ///
    /// `leadingOverhang` is how far past the row's leading edge the outline reaches: 6 pt
    /// matches a lit section's; a sidebar with disclosure chevrons on its rows takes 16, so the
    /// chevron sits inside the outline rather than under its edge.
    public func sidebarSelection(_ isSelected: Bool, leadingOverhang: CGFloat = 6) -> some View {
      modifier(SidebarSelectionOutline(isSelected: isSelected, leadingOverhang: leadingOverhang))
    }

    /// The one row a drag would land in: its own colour's border over a fainter wash, over the
    /// span a selection takes, so the two read as one family.
    public func sidebarDropOutline(
      isLit: Bool, tint: Color, leadingOverhang: CGFloat = 6
    ) -> some View {
      modifier(
        SidebarDropOutline(isLit: isLit, tint: tint, leadingOverhang: leadingOverhang))
    }
  }

  /// The span a sidebar row's outline covers: a row is only as wide as its text, the outline
  /// spans the sidebar, out past the text as the table's own selection does.
  private struct RowOutlineSpan<Outline: View>: ViewModifier {
    let leadingOverhang: CGFloat
    let outline: Outline

    func body(content: Content) -> some View {
      content
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
          outline
            .padding(.leading, -leadingOverhang)
            .padding(.trailing, -6)
            .padding(.vertical, -3)
        }
    }
  }

  private struct SidebarSelectionOutline: ViewModifier {
    @Environment(\.controlActiveState) private var activeState
    let isSelected: Bool
    let leadingOverhang: CGFloat

    func body(content: Content) -> some View {
      let tint = activeState == .inactive ? Color.secondary : Color.accentColor
      let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
      content.modifier(
        RowOutlineSpan(
          leadingOverhang: leadingOverhang,
          outline:
            shape
            .fill(isSelected ? tint.opacity(0.12) : .clear)
            .strokeBorder(isSelected ? tint.opacity(0.9) : .clear, lineWidth: 1.5)))
    }
  }

  private struct SidebarDropOutline: ViewModifier {
    let isLit: Bool
    let tint: Color
    let leadingOverhang: CGFloat

    func body(content: Content) -> some View {
      let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
      content
        .modifier(
          RowOutlineSpan(
            leadingOverhang: leadingOverhang,
            outline:
              shape
              .fill(isLit ? tint.opacity(0.08) : .clear)
              .strokeBorder(isLit ? tint : .clear, lineWidth: 2))
        )
        .animation(.easeOut(duration: 0.15), value: isLit)
    }
  }
#endif
