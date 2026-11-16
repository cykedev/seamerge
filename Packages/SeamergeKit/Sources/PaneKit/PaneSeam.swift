import AppKit

/// The seam between two panes side by side that connect their changes rather than line up their
/// rows: for each changed block, a band from its rows in the left pane to its rows in the right.
///
/// The top and bottom edges of a band are cubic curves that leave and reach the panes level. A band
/// goes over from the tint of the block on the left to its tint on the right, and its edges carry
/// on the hairlines at the edges of the block. Where a pane has no rows in the block, its end
/// of the band is a point on the hairline that marks the place, so that the band is a wedge.
/// Unchanged rows have no band, nor have blocks in which the two panes do not differ
/// (``blocksWithoutBand``).
///
/// The seam draws only the bands in view, from the blocks of the panes, their rows as they show
/// them and where they are scrolled to; it lays out no text. It takes no clicks, so that the
/// divider below it stays draggable, and VoiceOver passes it by: the bands repeat what the place,
/// the tints and the marks of the panes say.
public final class PaneSeam: NSView {
  /// The pane to the left of the seam.
  public private(set) weak var leftPane: PaneView?

  /// The pane to the right of the seam.
  public private(set) weak var rightPane: PaneView?

  /// The fonts, metrics and colors of the panes.
  public var theme = Theme() {
    didSet { needsDisplay = true }
  }

  /// The blocks in which the panes on either side do not differ, which get no band, as where
  /// only the other side of a merge changed; none at first.
  public var blocksWithoutBand = IndexSet() {
    didSet {
      if blocksWithoutBand != oldValue {
        needsDisplay = true
      }
    }
  }

  /// Creates the seam between `leftPane` and `rightPane`, which tell it when what they show
  /// changes, in place of any seam they had on that side.
  public init(between leftPane: PaneView, and rightPane: PaneView) {
    self.leftPane = leftPane
    self.rightPane = rightPane
    super.init(frame: .zero)
    // Views draw beyond their bounds unless told otherwise, and the dirty rectangle may reach
    // past them.
    clipsToBounds = true
    attach()
  }

  /// Seams are never archived.
  public required init?(coder: NSCoder) {
    nil
  }

  isolated deinit {
    detach()
  }

  /// A seam taken out of its view stops hearing from its panes; put back, it hears again.
  public override func viewDidMoveToSuperview() {
    super.viewDidMoveToSuperview()
    if superview == nil {
      detach()
    } else {
      attach()
    }
  }

  /// Has the panes tell the seam when what they show changes.
  private func attach() {
    leftPane?.trailingSeam = self
    rightPane?.leadingSeam = self
  }

  /// Has the panes stop telling the seam, if it is still theirs.
  private func detach() {
    if leftPane?.trailingSeam === self {
      leftPane?.trailingSeam = nil
    }
    if rightPane?.leadingSeam === self {
      rightPane?.leadingSeam = nil
    }
  }

  public override var isFlipped: Bool { true }

  public override var isOpaque: Bool { true }

  /// Clicks and drags pass through to the divider below.
  public override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }

  public override func isAccessibilityElement() -> Bool {
    false
  }

  public override func accessibilityChildren() -> [Any]? {
    []
  }

  public override func draw(_ dirtyRect: NSRect) {
    let dirtyRect = dirtyRect.intersection(bounds)
    guard let context = NSGraphicsContext.current?.cgContext, !dirtyRect.isEmpty else { return }
    Theme.backgroundColor.setFill()
    dirtyRect.fill()
    if let area = textArea {
      context.saveGState()
      context.clip(to: area)
      for band in bands where band.verticalExtent.overlaps(dirtyRect.minY...dirtyRect.maxY) {
        draw(band, in: context)
      }
      context.restoreGState()
    }
    let hairline = hairlineWidth
    NSColor.separatorColor.setFill()
    for x in [bounds.minX, bounds.maxX - hairline] {
      CGRect(x: x, y: dirtyRect.minY, width: hairline, height: dirtyRect.height).fill()
    }
  }

  /// A band as the seam draws it: the vertical extent of its block at either edge of the seam,
  /// in the seam's coordinates, measured along the hairlines at the block's edges.
  struct Band: Equatable {
    /// The index of the block among the panes' blocks.
    var block: Int
    /// From the hairline at the top of the block to the one at its bottom, in the left pane.
    var left: ClosedRange<CGFloat>
    /// From the hairline at the top of the block to the one at its bottom, in the right pane.
    var right: ClosedRange<CGFloat>
    /// How the block's rows are tinted in the left pane.
    var leftStyle: BlockStyle
    /// How the block's rows are tinted in the right pane.
    var rightStyle: BlockStyle
    /// Whether the block is the current one.
    var isCurrent: Bool

    /// From the top of the band to its bottom.
    var verticalExtent: ClosedRange<CGFloat> {
      min(left.lowerBound, right.lowerBound)...max(left.upperBound, right.upperBound)
    }
  }

  /// The bands of the blocks that reach into the text area of the panes, in block order, without
  /// the blocks that get none.
  ///
  /// A band whose block lies partly above or below the visible text keeps its ends where the
  /// rows are, beyond the area, so that its edges run as they would if all of it were in view.
  var bands: [Band] {
    guard let leftPane, let rightPane, let area = textArea else { return [] }
    let leftBlocks = leftPane.content.blocks
    let rightBlocks = rightPane.content.blocks
    let count = min(leftBlocks.count, rightBlocks.count)
    let first = (0..<count).partitioningIndex { index in
      max(extent(of: index, in: leftPane).upperBound, extent(of: index, in: rightPane).upperBound)
        >= area.minY
    }
    var bands: [Band] = []
    for index in first..<count {
      let left = extent(of: index, in: leftPane)
      let right = extent(of: index, in: rightPane)
      guard min(left.lowerBound, right.lowerBound) <= area.maxY else { break }
      guard !blocksWithoutBand.contains(index) else { continue }
      bands.append(
        Band(
          block: index, left: left, right: right, leftStyle: leftBlocks[index].style,
          rightStyle: rightBlocks[index].style,
          isCurrent: leftPane.currentBlock == index || rightPane.currentBlock == index))
    }
    return bands
  }

  /// The part of the seam beside the visible text of the panes, below their headers.
  private var textArea: CGRect? {
    let areas = [leftPane, rightPane].compactMap { pane -> CGRect? in
      guard let pane, pane.window === window, !pane.isHiddenOrHasHiddenAncestor else { return nil }
      return convert(pane.clipView.bounds, from: pane.clipView)
    }
    guard let first = areas.first else { return nil }
    let top = areas.map(\.minY).reduce(first.minY, max)
    let bottom = areas.map(\.maxY).reduce(first.maxY, min)
    guard bottom > top else { return nil }
    return CGRect(x: bounds.minX, y: top, width: bounds.width, height: bottom - top)
  }

  /// The vertical extent of block `index` in `pane`, in the seam's coordinates, from the middle
  /// of the hairline at its top to the middle of the one at its bottom; for a block without
  /// rows, the middle of the hairline that marks its place.
  private func extent(of index: Int, in pane: PaneView) -> ClosedRange<CGFloat> {
    let rows = pane.content.blocks[index].rows
    let span = pane.verticalSpan(ofRows: rows)
    let offset = convert(CGPoint.zero, from: pane.documentView).y
    let hairline = hairlineWidth
    guard !rows.isEmpty else {
      // The hairline lies at the top of the row below the boundary, or at the bottom of the last
      // row at the end of the text.
      let below = pane.content.hairlineRow(ofBoundary: rows.lowerBound) == rows.lowerBound
      let y = span.lowerBound + offset + (below ? hairline / 2 : -hairline / 2)
      return y...y
    }
    return (span.lowerBound + offset + hairline / 2)...(span.upperBound + offset - hairline / 2)
  }

  /// The thickness of a hairline: one pixel of the screen.
  private var hairlineWidth: CGFloat {
    1 / (window?.backingScaleFactor ?? 2)
  }

  /// Fills `band` and draws its edges.
  private func draw(_ band: Band, in context: CGContext) {
    let shape = outline(of: band)
    let fills = fillColors(of: band)
    if let fills {
      context.saveGState()
      context.addPath(shape.area)
      context.clip()
      drawGradient(from: fills.left, to: fills.right, in: context)
      context.restoreGState()
    }
    let edges = edgeColors(of: band)
    guard let edges else { return }
    context.saveGState()
    context.setLineWidth(hairlineWidth)
    for edge in [shape.top, shape.bottom] {
      context.addPath(edge)
    }
    context.replacePathWithStrokedPath()
    context.clip()
    drawGradient(from: edges.left, to: edges.right, in: context)
    context.restoreGState()
  }

  /// The area of `band` and its top and bottom edges.
  private func outline(of band: Band) -> (area: CGPath, top: CGPath, bottom: CGPath) {
    let (left, right) = (bounds.minX, bounds.maxX)
    func edge(from start: CGFloat, to end: CGFloat) -> CGPath {
      let path = CGMutablePath()
      path.move(to: CGPoint(x: left, y: start))
      add(from: start, to: end, to: path)
      return path
    }
    func add(from start: CGFloat, to end: CGFloat, to path: CGMutablePath) {
      let origin = CGPoint(x: path.currentPoint.x, y: start)
      let target = CGPoint(x: origin.x == left ? right : left, y: end)
      let controls = Self.controlPoints(from: origin, to: target)
      path.addCurve(to: target, control1: controls.first, control2: controls.second)
    }
    let area = CGMutablePath()
    area.move(to: CGPoint(x: left, y: band.left.lowerBound))
    add(from: band.left.lowerBound, to: band.right.lowerBound, to: area)
    area.addLine(to: CGPoint(x: right, y: band.right.upperBound))
    add(from: band.right.upperBound, to: band.left.upperBound, to: area)
    area.closeSubpath()
    return (
      area, edge(from: band.left.lowerBound, to: band.right.lowerBound),
      edge(from: band.left.upperBound, to: band.right.upperBound)
    )
  }

  /// The control points of the cubic curve of an edge from `start` at one side of the seam to
  /// `end` at the other, which leaves and reaches the panes level.
  ///
  /// The control points lie half way across, as for the bands of a few rows, while the edge
  /// rises or falls by up to twice the width of the seam. Beyond that they move further across,
  /// up to nine tenths of the way at eight times the width, so that a steep edge bends over more
  /// of the width rather than turning sharply where it reaches a pane, as at the point of a
  /// wedge. They stay at the heights of the ends, so the curve never goes beyond them.
  static func controlPoints(
    from start: CGPoint, to end: CGPoint
  ) -> (first: CGPoint, second: CGPoint) {
    let width = abs(end.x - start.x)
    let steepness = width > 0 ? abs(end.y - start.y) / width : 0
    let progress = min(max((steepness - 2) / 6, 0), 1)
    let share = 0.5 + 0.4 * progress * progress * (3 - 2 * progress)
    let across = end.x - start.x
    return (
      CGPoint(x: start.x + across * share, y: start.y),
      CGPoint(x: end.x - across * share, y: end.y)
    )
  }

  /// The fill of `band` at its left and right end, or `nil` if neither side is tinted.
  private func fillColors(of band: Band) -> (left: NSColor, right: NSColor)? {
    let left = theme.rowFill(for: band.leftStyle, isFiller: false, isCurrent: band.isCurrent)
    let right = theme.rowFill(for: band.rightStyle, isFiller: false, isCurrent: band.isCurrent)
    guard left != nil || right != nil else { return nil }
    return (left ?? .clear, right ?? .clear)
  }

  /// The color of the edges of `band` at its left and right end, or `nil` if neither side is
  /// tinted.
  private func edgeColors(of band: Band) -> (left: NSColor, right: NSColor)? {
    let left = theme.edgeColor(between: nil, and: band.leftStyle, isOnlyBoundary: false)
    let right = theme.edgeColor(between: nil, and: band.rightStyle, isOnlyBoundary: false)
    guard left != nil || right != nil else { return nil }
    return (left ?? .clear, right ?? .clear)
  }

  /// Fills the clipped area with a gradient across the seam, from `left` to `right`.
  private func drawGradient(from left: NSColor, to right: NSColor, in context: CGContext) {
    let colors = [left.cgColor, right.cgColor] as CFArray
    guard
      let space = CGColorSpace(name: CGColorSpace.sRGB),
      let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])
    else { return }
    context.drawLinearGradient(
      gradient, start: CGPoint(x: bounds.minX, y: 0), end: CGPoint(x: bounds.maxX, y: 0),
      options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
  }
}
