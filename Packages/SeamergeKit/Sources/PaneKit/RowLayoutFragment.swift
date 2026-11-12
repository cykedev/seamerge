import AppKit

/// A layout fragment that draws its rows the way a pane shows them: the row fills across the
/// full width of the pane, the highlights of changed runs, the selection, the text in the middle
/// of its row, and the marks of removed text.
///
/// AppKit draws its own selection opaquely below the fragments, where it would hide the tint of
/// a row. The fragment therefore covers it with the text background and draws the selection
/// itself, translucent and above the tint, so that the tint stays visible within a selection.
///
/// The fragment asks its painter what to draw each time it draws, since TextKit keeps fragments
/// across changes of layout; after a change, the pane has the fragments of the rows drawn again.
final class RowLayoutFragment: NSTextLayoutFragment {
  /// A run of text within the fragment, as UTF-16 offsets into the text, with its fill.
  struct Run: Sendable {
    var range: Range<Int>
    var fill: NSColor
  }

  /// A place within a line where a side removed text, as a UTF-16 offset into the text, with the
  /// color of its mark.
  struct Removal: Sendable {
    var offset: Int
    var color: NSColor
  }

  /// How far the fragment's drawing reaches beyond its glyphs, which changes only with the width
  /// of the pane and the theme.
  struct Extent: Sendable {
    /// The distance from the left edge of the text view to the text container.
    var containerInset: CGFloat
    /// The width of the text view, across which the rows are filled.
    var width: CGFloat
    /// How far the text is drawn above the place where TextKit lays it out, so that it sits in
    /// the middle of the row.
    var textLift: CGFloat
    /// The width of the mark of removed text.
    var removalMarkWidth: CGFloat
    /// The width of the seam of background color around the mark of removed text.
    var removalMarkSeam: CGFloat
  }

  /// Everything the fragment draws besides its glyphs.
  struct Painting: Sendable {
    /// How far the drawing reaches.
    var extent: Extent
    /// The fill of each row, or `nil` for a row on the text background.
    var rowFills: [NSColor?]
    /// The color of the text background, which covers AppKit's selection.
    var background: NSColor
    /// The height of the band of a line's text, centered in the row: the height of run fills
    /// and removal marks.
    var textBandHeight: CGFloat
    /// The changed runs within the fragment's lines.
    var runs: [Run]
    /// The selected runs within the fragment's lines, with the fill of the selection.
    var selections: [Run]
    /// The places within the fragment's lines where text was removed.
    var removals: [Removal]
  }

  /// The offset at which the fragment's paragraph starts in the text.
  let paragraphStart: Int

  /// The rows that the fragment lays out.
  let rows: Range<Int>

  /// The height of a row.
  let rowHeight: CGFloat

  /// Supplies what the fragment draws besides its glyphs.
  private weak var painter: (any RowPainter)?

  /// Creates a fragment for the paragraph `textElement`, which starts at `paragraphStart` and
  /// lays out `rows`.
  init(
    textElement: NSTextElement, range: NSTextRange?, paragraphStart: Int, rows: Range<Int>,
    rowHeight: CGFloat, painter: any RowPainter
  ) {
    self.paragraphStart = paragraphStart
    self.rows = rows
    self.rowHeight = rowHeight
    self.painter = painter
    super.init(textElement: textElement, range: range)
  }

  /// What the fragment draws now, or `nil` once its pane is gone.
  ///
  /// AppKit lays out and draws text views on the main thread.
  private var painting: Painting? {
    guard let painter else { return nil }
    let rows = rows
    return MainActor.assumeIsolated { painter.painting(forRows: rows) }
  }

  /// How far the fragment's drawing reaches now, or `nil` once its pane is gone.
  private var extent: Extent? {
    guard let painter else { return nil }
    return MainActor.assumeIsolated { painter.extent }
  }

  /// Panes are never archived.
  required init?(coder: NSCoder) {
    nil
  }

  /// The frame of the fragment on the grid: its first row times the row height.
  ///
  /// TextKit places a fragment that it has not laid out yet by an estimate from the number of
  /// characters before it, which misses rows of a long file by thousands of points. The grid
  /// knows the place exactly.
  override var layoutFragmentFrame: CGRect {
    let frame = super.layoutFragmentFrame
    return CGRect(
      x: frame.minX, y: CGFloat(rows.lowerBound) * rowHeight, width: frame.width,
      height: CGFloat(rows.count) * rowHeight)
  }

  override var renderingSurfaceBounds: CGRect {
    guard let extent else { return super.renderingSurfaceBounds }
    let markReach = extent.removalMarkWidth + extent.removalMarkSeam
    return super.renderingSurfaceBounds.offsetBy(dx: 0, dy: -extent.textLift)
      .insetBy(dx: -markReach, dy: -extent.removalMarkSeam)
      .union(rowsBounds(extent))
  }

  override func draw(at point: CGPoint, in context: CGContext) {
    guard let painting else { return super.draw(at: point, in: context) }
    let extent = painting.extent
    let rows = rowsBounds(extent).offsetBy(dx: point.x, dy: point.y)
    context.setFillColor(painting.background.cgColor)
    context.fill(rows)
    for (index, fill) in painting.rowFills.enumerated() {
      guard let fill else { continue }
      context.setFillColor(fill.cgColor)
      context.fill(
        CGRect(
          x: rows.minX, y: rows.minY + CGFloat(index) * rowHeight, width: rows.width,
          height: rowHeight))
    }
    for run in painting.runs {
      for rect in runRects(run.range, fullHeight: false, painting) {
        context.setFillColor(run.fill.cgColor)
        context.fill(rect.offsetBy(dx: point.x, dy: point.y))
      }
    }
    for selection in painting.selections {
      for rect in runRects(selection.range, fullHeight: true, painting) {
        context.setFillColor(selection.fill.cgColor)
        context.fill(rect.offsetBy(dx: point.x, dy: point.y))
      }
    }
    super.draw(at: CGPoint(x: point.x, y: point.y - extent.textLift), in: context)
    for removal in painting.removals {
      guard let mark = markRect(for: removal, painting)?.offsetBy(dx: point.x, dy: point.y) else {
        continue
      }
      // A seam of background color keeps the mark clear on a selection of a similar color.
      let seam = mark.insetBy(dx: -extent.removalMarkSeam, dy: -extent.removalMarkSeam)
      fillRoundedRect(seam, color: painting.background, in: context)
      fillRoundedRect(mark, color: removal.color, in: context)
    }
  }

  /// The rows of the fragment across the full width of the text view, relative to its origin.
  private func rowsBounds(_ extent: Extent) -> CGRect {
    CGRect(
      x: -(super.layoutFragmentFrame.minX + extent.containerInset), y: 0,
      width: extent.width, height: CGFloat(rows.count) * rowHeight)
  }

  /// The rectangles of the text from offset `range.lowerBound` to `range.upperBound`, relative to
  /// the fragment's origin: one per line, as high as the text band or the whole row.
  ///
  /// A range that reaches past the end of a line includes its line feed and reaches to the right
  /// edge of the pane, as a selection of whole lines does.
  private func runRects(_ range: Range<Int>, fullHeight: Bool, _ painting: Painting) -> [CGRect] {
    textLineFragments.enumerated().compactMap { lineIndex, line in
      let lineRange = line.characterRange
      let text = line.attributedString.string as NSString
      // The text of the line, without its line feed.
      let textEnd =
        lineRange.upperBound > lineRange.lowerBound
          && text.character(at: lineRange.upperBound - 1) == 0x0A
        ? lineRange.upperBound - 1 : lineRange.upperBound
      let start = max(range.lowerBound - paragraphStart, lineRange.lowerBound)
      let end = min(range.upperBound - paragraphStart, textEnd)
      let reachesEnd = range.upperBound - paragraphStart > textEnd
      guard start < end || (reachesEnd && start <= end) else { return nil }
      let left = line.typographicBounds.minX + line.locationForCharacter(at: start).x
      let right =
        reachesEnd
        ? rowsBounds(painting.extent).maxX
        : line.typographicBounds.minX + line.locationForCharacter(at: end).x
      let height = fullHeight ? rowHeight : painting.textBandHeight
      let top = CGFloat(lineIndex) * rowHeight + (rowHeight - height) / 2
      return CGRect(x: left, y: top, width: right - left, height: height)
    }
  }

  private func fillRoundedRect(_ rect: CGRect, color: NSColor, in context: CGContext) {
    let radius = rect.width / 2
    context.setFillColor(color.cgColor)
    context.addPath(
      CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.fillPath()
  }

  /// The mark of `removal` relative to the fragment's origin: a rounded bar in the middle of
  /// its row, and in the middle of the gap that the eye sees between the characters around it.
  private func markRect(for removal: Removal, _ painting: Painting) -> CGRect? {
    let index = removal.offset - paragraphStart
    guard
      let line = textLineFragments.first(where: {
        $0.characterRange.lowerBound <= index && index <= $0.characterRange.upperBound
      })
    else { return nil }
    let range = line.characterRange
    func cellStart(_ index: Int) -> CGFloat {
      line.typographicBounds.minX + line.locationForCharacter(at: index).x
    }
    var left = cellStart(index)
    var right = left
    if index > range.lowerBound {
      // The ink of the character before, or all of its cell if it leaves none.
      let previousStart = cellStart(index - 1)
      left = inkBounds(of: line, at: index - 1).map { previousStart + $0.maxX } ?? previousStart
    }
    if index < range.upperBound {
      let nextEnd = cellStart(index + 1)
      right = inkBounds(of: line, at: index).map { cellStart(index) + $0.minX } ?? nextEnd
    }
    let width = painting.extent.removalMarkWidth
    let height = painting.textBandHeight
    return CGRect(
      x: (left + right) / 2 - width / 2, y: (rowHeight - height) / 2, width: width,
      height: height)
  }

  /// The bounds of the ink of the character at `index` in `line`, relative to the start of its
  /// cell, or `nil` if it leaves none, like a space, or its glyph is not in the line's font.
  private func inkBounds(of line: NSTextLineFragment, at index: Int) -> CGRect? {
    let text = line.attributedString
    guard
      index < text.length,
      let font = text.attribute(.font, at: index, effectiveRange: nil) as? NSFont
    else { return nil }
    var character = (text.string as NSString).character(at: index)
    var glyph = CGGlyph()
    guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1) else { return nil }
    let bounds = font.boundingRect(forCGGlyph: glyph)
    return bounds.isEmpty ? nil : bounds
  }
}

/// Supplies what a fragment draws besides its glyphs: its pane, which knows the current block,
/// the selection and the highlights.
@MainActor
protocol RowPainter: AnyObject, Sendable {
  /// How far the drawing of every fragment reaches now.
  var extent: RowLayoutFragment.Extent { get }

  /// What the fragment that lays out `rows` draws now.
  func painting(forRows rows: Range<Int>) -> RowLayoutFragment.Painting
}
