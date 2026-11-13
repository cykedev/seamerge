import AppKit

/// Where the parts of a row of the decision column stand: the bar of toggles with its segments
/// for A, the base and B, and beside it the place for the arrow that resets the block.
///
/// The bar takes its size from the rows of the text: two points lower than a row, so that the
/// bars of blocks on lines one after the other keep a gap, within the limits of the theme, and
/// with segments about as wide as the bar is high. Each part has a slot of its own whose position
/// and width are the same in every row, whatever the row shows, so that the toggles of all
/// blocks line up in columns. A row is at least as high as the room of a click and centered on
/// the place that its block asks for; its edges and those of the bar lie on whole pixels.
struct DecisionColumnLayout {
  /// A slot of a row, from leading to trailing.
  enum Slot: CaseIterable {
    case a
    case base
    case b
    /// The place beside the bar for the reset arrow.
    case place
  }

  /// The slot of the toggle of `role`, or `nil` for the conflict, which has no toggle.
  static func slot(of role: ColorRole) -> Slot? {
    switch role {
    case .a: .a
    case .base: .base
    case .b: .b
    case .conflict: nil
    }
  }

  /// The height of a row of the text.
  let rowHeight: CGFloat

  /// The layout for the rows of the text of `theme`.
  init(theme: Theme) {
    rowHeight = theme.rowHeight
  }

  /// The height of the bar as it is drawn: a row less the gap between bars, within the limits of
  /// the theme.
  var barHeight: CGFloat {
    let height = (rowHeight - Theme.toggleBarGap).rounded(.down)
    return min(max(height, Theme.toggleBarHeights.lowerBound), Theme.toggleBarHeights.upperBound)
  }

  /// The width of each segment of the bar and of the place beside it: a little wider than the
  /// bar is high, and never narrower than the room of a click.
  var segmentWidth: CGFloat {
    max(barHeight + Theme.toggleSegmentPadding, Theme.decisionControlSize)
  }

  /// The height of a row of the column: the room of a click, a point more where that keeps the
  /// bar on whole points in its middle.
  var height: CGFloat {
    let room = Theme.decisionControlSize
    return (room - barHeight).truncatingRemainder(dividingBy: 2) == 0 ? room : room + 1
  }

  /// The frame of `slot` within a row whose leading edge is at x 0: the segments of the bar side
  /// by side, then the place after a gap.
  func frame(of slot: Slot) -> CGRect {
    let x: CGFloat =
      switch slot {
      case .a: 0
      case .base: segmentWidth
      case .b: 2 * segmentWidth
      case .place: 3 * segmentWidth + Theme.decisionPlaceGap
      }
    return CGRect(x: x, y: 0, width: segmentWidth, height: height)
  }

  /// The bar of toggles as it is drawn within a row: across the segments, as high as the bar,
  /// in the middle of the row.
  var barRect: CGRect {
    let segments = frame(of: .a).union(frame(of: .b))
    return segments.insetBy(dx: 0, dy: (height - barHeight) / 2)
  }

  /// The width of a row: every slot side by side.
  var rowWidth: CGFloat {
    frame(of: .place).maxX
  }

  /// The width of the column: a row with the inset on both sides, rounded up to the layout grid.
  var columnWidth: CGFloat {
    let width = rowWidth + 2 * Theme.decisionColumnInset
    return (width / Theme.layoutGrid).rounded(.up) * Theme.layoutGrid
  }

  /// The least distance between the middles of the rows of two blocks: a row of the text, so
  /// that the bars of blocks on lines one after the other stay on their lines, and only bars
  /// that would stand on the same line move apart.
  var rowSpacing: CGFloat {
    rowHeight
  }

  /// The size of the letters of the bar, which grow and shrink with it, never below the smallest
  /// size of the interface.
  var letterSize: CGFloat {
    max((barHeight * Theme.toggleLetterRatio).rounded(), Theme.smallestFontSize)
  }

  /// The frame of a row in the column whose middle is as close to `center` as whole pixels at
  /// `scale` allow.
  func rowFrame(centeredOn center: CGFloat, scale: CGFloat) -> CGRect {
    let top = center - height / 2
    return CGRect(
      x: Theme.decisionColumnInset, y: (top * scale).rounded() / scale, width: rowWidth,
      height: height)
  }
}
