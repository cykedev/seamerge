import AppKit
import PaneKit

/// The places a pane scrolls its text to, which lie on whole pixels of the screen.
enum WholePixels {
  /// The styles the system gives scrollers: a legacy scroller below a pane takes its height from
  /// the text, so that the reading line and the places of the panes that follow lie elsewhere.
  ///
  /// The system picks the style from the pointing devices connected and may change it while the
  /// tests run, so tests that depend on it set each style in turn.
  static let scrollerStyles = [NSScroller.Style.overlay, .legacy]

  /// Whether `origin`, where a pane stands, is the place on whole pixels at `scale` nearest to
  /// `exact`, where the pane would stand if it could stand anywhere.
  ///
  /// A pane scrolls its text to whole pixels only, so that its hairlines meet the edges of the
  /// seams beside it; it then lies half a pixel at most from the exact place, at a tie on either
  /// side. The ten-thousandth of a point beyond takes up the rounding errors of `exact`.
  static func isNearest(_ origin: CGFloat, to exact: CGFloat, scale: CGFloat) -> Bool {
    (origin * scale).rounded() == origin * scale && abs(origin - exact) <= 0.5 / scale + 0.0001
  }
}

extension PaneView {
  /// Gives the scrollers of the pane `style`, as the system does when the user changes when
  /// scroll bars show or connects a mouse, and lays the pane out for it.
  func setScrollerStyle(_ style: NSScroller.Style) {
    documentView.enclosingScrollView?.scrollerStyle = style
    layoutSubtreeIfNeeded()
  }
}
