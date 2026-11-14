import AppKit
import PaneKit

extension PaneView {
  /// How a pane moves to a place it scrolls to.
  enum ScrollMotion {
    /// The pane moves there at once.
    case cut

    /// The pane glides there if the place is at most about a window's height away, so that the
    /// eye can follow, and moves there at once otherwise.
    case glideWithinAWindowHeight
  }

  /// How long a pane glides to a place it jumps to.
  static let glideDuration: TimeInterval = 0.2

  /// Whether the pane takes up room in its window: its split view item is neither collapsed nor
  /// squeezed to nothing.
  var isShown: Bool {
    window != nil && !isHiddenOrHasHiddenAncestor && bounds.height > 0 && bounds.width > 0
  }

  /// The row at the reading line, and how far down that row the reading line passes, from 0 at
  /// its top to 1 at its bottom.
  var rowAtReadingLine: (row: Int, fraction: CGFloat) {
    let visible = documentView.visibleRect
    let y = visible.minY + Theme.readingLine * visible.height
    let row = hit(at: convert(CGPoint(x: 0, y: y), from: documentView)).row
    let span = verticalSpan(ofRows: row..<row + 1)
    let height = span.upperBound - span.lowerBound
    return (row, height > 0 ? min(max((y - span.lowerBound) / height, 0), 1) : 0)
  }

  /// Whether every one of `rows` is in full view; for an empty range, whether the boundary it
  /// lies on is.
  func showsWhole(rows: Range<Int>) -> Bool {
    let visible = documentView.visibleRect
    let span = verticalSpan(ofRows: rows)
    return span.lowerBound >= visible.minY && span.upperBound <= visible.maxY
  }

  /// Scrolls so that `row` comes to rest at the reading line, or as near to it as the text
  /// allows, with `motion`; the panes coupled with this one follow.
  ///
  /// - Parameter fraction: How far down the row the reading line passes, from 0 at its top to 1
  ///   at its bottom.
  func scroll(toPlaceRowAtReadingLine row: Int, fraction: CGFloat = 0, motion: ScrollMotion) {
    guard let scrollView = documentView.enclosingScrollView else { return }
    let clipView = scrollView.contentView
    let visible = clipView.bounds
    let range = max(documentView.frame.height - visible.height, 0)
    let span = verticalSpan(ofRows: row..<row + 1)
    let y =
      span.lowerBound + fraction * (span.upperBound - span.lowerBound) - Theme.readingLine
      * visible.height
    let origin = CGPoint(x: visible.minX, y: min(max(y, 0), range).rounded())
    guard origin != visible.origin else { return }
    let windowHeight = window?.contentLayoutRect.height ?? visible.height
    if motion == .glideWithinAWindowHeight && abs(origin.y - visible.minY) <= windowHeight {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = Self.glideDuration
        clipView.animator().setBoundsOrigin(origin)
      }
    } else {
      clipView.scroll(to: origin)
      scrollView.reflectScrolledClipView(clipView)
    }
  }
}
