import AppKit

extension PaneTextView {
  /// Fits the span of the view that its fragments draw to the part in view: that part and as
  /// much again on either side, in steps of its width, so that scrolling sideways has the
  /// fragments drawn anew only as it reaches beyond.
  ///
  /// TextKit gives each fragment in view a surface as wide as the fragment draws. Across the full
  /// width of a view that is as wide as its longest line, a file of lines thousands of characters
  /// long would take surfaces of hundreds of megabytes, all drawn with every new row.
  func updateDrawnSpan() {
    let span = Self.drawnSpan(showing: visibleRect, width: bounds.width)
    guard span != drawnSpan else { return }
    drawnSpan = span
    // The fragments in view take surfaces of the new span as TextKit lays out the view again.
    needsLayout = true
    setNeedsDisplayOfFragments(in: bounds)
  }

  /// The span of a view `width` wide that its fragments draw while `visible` is in view: all of
  /// it in a view up to three times as wide as the part in view.
  static func drawnSpan(showing visible: CGRect, width: CGFloat) -> Range<CGFloat> {
    let step = visible.width
    guard step > 0, width > 3 * step else { return 0..<max(width, 0) }
    let start = max(((visible.minX / step).rounded(.down) - 1) * step, 0)
    let end = min(((visible.maxX / step).rounded(.up) + 1) * step, width)
    return start..<max(end, start)
  }
}
