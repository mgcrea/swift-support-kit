import CoreGraphics

/// Which of the app's own windows a point is on, as a pure function.
///
/// The app hit-tests its own windows front to back rather than asking the
/// window server what is on top there, so a window that another app's window
/// covers still takes the click. That is the point of driving it in the
/// background.
enum WindowPick {
  /// `windows` front to back, frames in AppKit's bottom-left screen space, and
  /// `point` already flipped into it. Edges are inside.
  static func window(at point: CGPoint, in windows: [(number: Int, frame: CGRect)]) -> Int? {
    windows.first { window in
      point.x >= window.frame.minX && point.x <= window.frame.maxX
        && point.y >= window.frame.minY && point.y <= window.frame.maxY
    }?.number
  }

  /// A top-left global point, as Cupertino sends it, in AppKit's bottom-left
  /// space, which is measured from the primary display's height.
  static func cocoa(_ point: CGPoint, primaryHeight: CGFloat) -> CGPoint {
    CGPoint(x: point.x, y: primaryHeight - point.y)
  }
}
