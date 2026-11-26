import SwiftUI

/// The stretch of a lit section's outline that one of its targets draws. A section is
/// outlined as one rounded rectangle, but a list draws each row on its own, so every row draws
/// its sides, and the rows at either end close it.
///
/// On the Mac the header is the outline's top. On iOS the header sits above the inset-grouped
/// card, so the card is what is outlined, from its first row to its last, and the header draws
/// nothing unless it is all there is.
public struct SectionOutline: OptionSet, Sendable {
  public let rawValue: Int

  public init(rawValue: Int) {
    self.rawValue = rawValue
  }

  public static let top = SectionOutline(rawValue: 1 << 0)
  public static let bottom = SectionOutline(rawValue: 1 << 1)
  public static let sides: SectionOutline = []

  /// A section's header. Collapsed, it shows no rows below, so it closes the outline on its
  /// own.
  public static func header(isCollapsed: Bool) -> SectionOutline? {
    if isCollapsed { return [.top, .bottom] }
    #if os(iOS)
      return nil
    #else
      return .top
    #endif
  }

  /// A row of a section, or the one row an empty section shows (both first and last).
  public static func row(isFirst: Bool, isLast: Bool) -> SectionOutline {
    var outline = SectionOutline.sides
    #if os(iOS)
      if isFirst { outline.insert(.top) }
    #endif
    if isLast { outline.insert(.bottom) }
    return outline
  }
}

extension View {
  /// Draws this target's stretch of a lit section's outline, `outline`, in `tint` over a faint
  /// wash of it; nil draws none. `isHeader` for the section's header, which the Mac sidebar
  /// insets differently from its rows.
  ///
  /// On iOS a row's stretch is its `listRowBackground`, so it follows the card's edge; on the
  /// Mac, whose sidebar draws no row background, it is grown to meet its neighbours, with the
  /// corners of the sidebar's selection.
  public func sectionDropOutline(
    _ outline: SectionOutline?, isLit: Bool, tint: Color, isHeader: Bool = false
  ) -> some View {
    modifier(
      SectionOutlineStroke(isLit: isLit, tint: tint, isHeader: isHeader, outline: outline))
  }
}

private struct SectionOutlineStroke: ViewModifier {
  let isLit: Bool
  let tint: Color
  let isHeader: Bool
  let outline: SectionOutline?

  func body(content: Content) -> some View {
    if let outline {
      #if os(iOS)
        if isHeader {
          content
            .background(stroke(outline, cornerRadius: 8).padding(-6))
            .animation(.easeOut(duration: 0.15), value: isLit)
        } else {
          content.listRowBackground(
            isLit
              ? ZStack {
                Color(uiColor: .secondarySystemGroupedBackground)
                // The card's own corner on iOS 26, measured: the card clips its end rows, so
                // a tighter corner loses its curve.
                stroke(outline, cornerRadius: 26)
              } : nil)
        }
      #else
        content
          // The sidebar insets a header 2 pt less than its rows at the leading edge and 14 pt
          // less at the trailing one, where its count would sit outside the rows' outline,
          // 2 pt from the divider. So the count comes in by those 14 pt, and the header's
          // outline is drawn over the rows' span rather than its own.
          .padding(.trailing, isHeader ? 14 : 0)
          // A row is only as wide as its text; the outline spans the sidebar.
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(
            stroke(outline, cornerRadius: 6)
              .padding(.leading, isHeader ? -4 : -6)
              .padding(.trailing, isHeader ? 14 - 6 : -6)
              .padding(.top, outline.contains(.top) ? -3 : -5)
              .padding(.bottom, outline.contains(.bottom) ? -3 : -5)
          )
          .animation(.easeOut(duration: 0.15), value: isLit)
      #endif
    } else {
      content
    }
  }

  /// The outline, over a faint wash of the same colour filling the stretch, rounded only where
  /// the outline closes.
  private func stroke(_ outline: SectionOutline, cornerRadius: CGFloat) -> some View {
    let top = outline.contains(.top) ? cornerRadius : 0
    let bottom = outline.contains(.bottom) ? cornerRadius : 0
    return ZStack {
      UnevenRoundedRectangle(
        topLeadingRadius: top, bottomLeadingRadius: bottom,
        bottomTrailingRadius: bottom, topTrailingRadius: top, style: .circular
      )
      .fill(isLit ? tint.opacity(0.08) : .clear)
      OutlineStretch(
        top: outline.contains(.top), bottom: outline.contains(.bottom),
        cornerRadius: cornerRadius, lineWidth: 2
      )
      .stroke(isLit ? tint : .clear, lineWidth: 2)
    }
  }
}

/// Both sides of a rectangle, and its top and bottom where they close it, rounded at the
/// closed corners. Inset by half the line on every edge it draws, so the stroke stays inside
/// the frame.
struct OutlineStretch: Shape {
  let top: Bool
  let bottom: Bool
  let cornerRadius: CGFloat
  let lineWidth: CGFloat

  nonisolated func path(in frame: CGRect) -> Path {
    let inset = lineWidth / 2
    let rect = CGRect(
      x: frame.minX + inset, y: frame.minY + (top ? inset : 0),
      width: frame.width - lineWidth,
      height: frame.height - (top ? inset : 0) - (bottom ? inset : 0))
    let radius = min(cornerRadius, rect.width / 2, rect.height / 2)
    let topLeft = CGPoint(x: rect.minX, y: rect.minY)
    let topRight = CGPoint(x: rect.maxX, y: rect.minY)
    let bottomLeft = CGPoint(x: rect.minX, y: rect.maxY)
    let bottomRight = CGPoint(x: rect.maxX, y: rect.maxY)

    var path = Path()
    // Up the left side, across the top, and down the right side; then back along the bottom,
    // or lift the pen for the left side again.
    path.move(to: CGPoint(x: rect.minX, y: bottom ? rect.maxY - radius : rect.maxY))
    if top {
      path.addArc(tangent1End: topLeft, tangent2End: topRight, radius: radius)
      path.addArc(tangent1End: topRight, tangent2End: bottomRight, radius: radius)
    } else {
      path.addLine(to: topLeft)
      path.move(to: topRight)
    }
    if bottom {
      path.addArc(tangent1End: bottomRight, tangent2End: bottomLeft, radius: radius)
      path.addArc(tangent1End: bottomLeft, tangent2End: topLeft, radius: radius)
      // Only a whole rectangle is one subpath; an open top already left it.
      if top { path.closeSubpath() }
    } else {
      path.addLine(to: bottomRight)
    }
    return path
  }
}
