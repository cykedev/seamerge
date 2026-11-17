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
  /// of the pane, the part of it in view and the theme.
  struct Extent: Sendable {
    /// The distance from the left edge of the text view to the text container.
    var containerInset: CGFloat
    /// The part of the width of the text view that the fragments draw, from its left edge:
    /// across it the rows are filled, and beyond it, far out of view, a long line draws nothing.
    var drawnSpan: Range<CGFloat>
    /// How far the text is drawn above the place where TextKit lays it out, so that it sits in
    /// the middle of the row.
    var textLift: CGFloat
    /// The width of the mark of removed text.
    var removalMarkWidth: CGFloat
    /// The width of the seam of background color around the mark of removed text.
    var removalMarkSeam: CGFloat
    /// The thickness of a hairline: one pixel of the screen.
    var hairline: CGFloat
  }

  /// Everything the fragment draws besides its glyphs.
  struct Painting: Sendable {
    /// How far the drawing reaches.
    var extent: Extent
    /// Whether the fragment's rows lie behind the bar of a collapsed run, which draws in their
    /// place.
    var isCollapsed: Bool
    /// The number of screen lines of each row: at least those of its text, more where a pane it
    /// lines up with wraps it more.
    var rowLines: [Int]
    /// The fills and hairlines of each row, which the gutter beside the text draws too.
    var shadings: [RowShading]
    /// The color of the text background, which covers AppKit's selection.
    var background: NSColor
    /// The height of the band of a line's text, centered in the row: the height of run fills
    /// and removal marks.
    var textBandHeight: CGFloat
    /// The changed runs within the fragment's lines.
    var runs: [Run]
    /// The matches of a search within the fragment's lines, with the color of their mark.
    var matches: [Run]
    /// The selected runs within the fragment's lines, with the fill of the selection.
    var selections: [Run]
    /// The places within the fragment's lines where text was removed.
    var removals: [Removal]
    /// What the invisible characters of the fragment's rows look like, or `nil` if they do not
    /// show.
    var invisibles: Invisibles?
  }

  /// The symbols for spaces, tabs and line endings.
  struct Invisibles: Sendable {
    /// How the line of each of the fragment's rows ends, or `nil` if only the places of ignored
    /// differences get symbols.
    var lineEndings: [LineEnding]?
    /// The places of ignored differences, as UTF-16 offsets into the text, sorted and apart,
    /// whose spaces and tabs get symbols in a color of their own.
    var places: [Range<Int>]
    /// The color of the symbols.
    var color: NSColor
    /// The color of the symbols in the places of ignored differences.
    var placeColor: NSColor
    /// The distance from the top of a row to the baseline of its text, as drawn.
    var baseline: CGFloat
  }

  /// The height of a row.
  let rowHeight: CGFloat

  /// Supplies what the fragment draws besides its glyphs.
  private weak var painter: (any RowPainter)?

  /// The version of the pane's text, which tells when the place of the fragment has to be found
  /// again.
  private let textVersion: TextVersion

  /// Where the fragment's paragraph starts in the text and the rows it lays out, as of the
  /// version of the text they were found in.
  private var cachedPlace: (version: Int, paragraphStart: Int, rows: Range<Int>)?

  /// Creates a fragment for the paragraph `textElement` of a text whose version `textVersion`
  /// counts.
  init(
    textElement: NSTextElement, range: NSTextRange?, rowHeight: CGFloat, textVersion: TextVersion,
    painter: any RowPainter
  ) {
    self.rowHeight = rowHeight
    self.textVersion = textVersion
    self.painter = painter
    super.init(textElement: textElement, range: range)
  }

  /// The offset at which the fragment's paragraph starts in the text.
  var paragraphStart: Int {
    place.paragraphStart
  }

  /// The rows that the fragment lays out.
  var rows: Range<Int> {
    place.rows
  }

  /// The lines that TextKit laid out, with the line of an empty last row moved to the first
  /// screen line of that row.
  ///
  /// TextKit puts that line right below the text of the row before it. Where a neighbor wraps
  /// the row before into more screen lines, the row takes them too, and the insertion point on
  /// the empty last row would stand among them.
  override var textLineFragments: [NSTextLineFragment] {
    let lines = super.textLineFragments
    guard rows.count > 1, let last = lines.last, rowIndex(of: last) == 1, let painter else {
      return lines
    }
    let firstRow = rows.lowerBound..<rows.lowerBound + 1
    let top =
      CGFloat(MainActor.assumeIsolated { painter.lines(ofRows: firstRow).count }) * rowHeight
    guard abs(last.typographicBounds.minY - top) > 0.5 else { return lines }
    if let moved = movedLine, moved.original === last, moved.line.typographicBounds.minY == top {
      return lines.dropLast() + [moved.line]
    }
    // TextKit finds lines again by identity, so the moved line stays the same object.
    let moved = EmptyRowLineFragment(last, top: top)
    movedLine = (last, moved)
    return lines.dropLast() + [moved]
  }

  /// The line of the empty last row as TextKit laid it out, and as the fragment moved it.
  private var movedLine: (original: NSTextLineFragment, line: NSTextLineFragment)?

  /// The places of the characters of each of the fragment's lines, found once for the lines
  /// that TextKit laid out.
  ///
  /// Finding them takes time in proportion to the length of the lines, and a fragment draws
  /// whenever its rows are drawn again: on a change of the selection, the current block or the
  /// matches of a search.
  private var lineCarets: [LineCarets] {
    let lines = textLineFragments
    if let cachedCarets, cachedCarets.lines.elementsEqual(lines, by: ===) {
      return cachedCarets.carets
    }
    let carets = lines.map(LineCarets.init)
    cachedCarets = (lines, carets)
    return carets
  }

  private var cachedCarets: (lines: [NSTextLineFragment], carets: [LineCarets])?

  /// Lets go of the places of the characters along with the lines that TextKit lays out anew,
  /// so that the old lines do not outlive the layout.
  override func invalidateLayout() {
    cachedCarets = nil
    super.invalidateLayout()
  }

  /// Where the fragment's paragraph starts and the rows it lays out.
  ///
  /// TextKit keeps the fragments of paragraphs that an edit does not touch and moves their
  /// elements, so the place is found again from the element once the text has changed. TextKit
  /// asks for the frames of many fragments in a row to find the one at a position, so the place
  /// is kept until then.
  private var place: (paragraphStart: Int, rows: Range<Int>) {
    let version = textVersion.value
    if let cachedPlace, cachedPlace.version == version {
      return (cachedPlace.paragraphStart, cachedPlace.rows)
    }
    guard let painter else { return (0, 0..<1) }
    var offsets = 0..<0
    if let element = textElement, let manager = element.textContentManager,
      let range = element.elementRange
    {
      let documentStart = manager.documentRange.location
      let start = manager.offset(from: documentStart, to: range.location)
      offsets = start..<max(manager.offset(from: documentStart, to: range.endLocation), start)
    }
    let rows = MainActor.assumeIsolated {
      painter.rows(ofParagraphFrom: offsets.lowerBound, to: offsets.upperBound)
    }
    cachedPlace = (version, offsets.lowerBound, rows)
    return (offsets.lowerBound, rows)
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

  /// The screen lines that the fragment takes: those of its rows, or the one of a bar.
  private var lines: Range<Int> {
    guard let painter else { return rows }
    let rows = rows
    return MainActor.assumeIsolated { painter.lines(ofRows: rows) }
  }

  /// The frame of the fragment on the grid: its first screen line times the row height.
  ///
  /// TextKit places a fragment that it has not laid out yet by an estimate from the number of
  /// characters before it, which misses rows of a long file by thousands of points. The grid
  /// knows the place exactly.
  override var layoutFragmentFrame: CGRect {
    let frame = super.layoutFragmentFrame
    let lines = lines
    return CGRect(
      x: frame.minX, y: CGFloat(lines.lowerBound) * rowHeight, width: frame.width,
      height: CGFloat(lines.count) * rowHeight)
  }

  /// The glyphs and the marks of the fragment within the drawn span, and its rows across it.
  ///
  /// TextKit makes a surface as large as this for each fragment in view, so a line thousands of
  /// characters long would take one as wide as all of them.
  override var renderingSurfaceBounds: CGRect {
    guard let extent else { return super.renderingSurfaceBounds }
    let markReach = extent.removalMarkWidth + extent.removalMarkSeam
    let rows = rowsBounds(extent)
    let text = super.renderingSurfaceBounds.offsetBy(dx: 0, dy: -extent.textLift)
      .insetBy(dx: -markReach, dy: -extent.removalMarkSeam)
    let drawnText = text.intersection(
      CGRect(x: rows.minX, y: text.minY, width: rows.width, height: text.height))
    return drawnText.isNull ? rows : drawnText.union(rows)
  }

  override func draw(at point: CGPoint, in context: CGContext) {
    guard let painting else { return super.draw(at: point, in: context) }
    guard !painting.isCollapsed else { return }
    let extent = painting.extent
    let rows = rowsBounds(extent).offsetBy(dx: point.x, dy: point.y)
    context.setFillColor(painting.background.cgColor)
    context.fill(rows)
    let textLines = textLinesOfRows(count: painting.rowLines.count)
    var top = rows.minY
    for index in painting.rowLines.indices {
      let height = CGFloat(painting.rowLines[index]) * rowHeight
      painting.shadings[index].draw(
        in: CGRect(x: rows.minX, y: top, width: rows.width, height: height),
        textLines: textLines[index], rowHeight: rowHeight, hairline: extent.hairline,
        context: context)
      top += height
    }
    let needsCarets =
      !painting.runs.isEmpty || !painting.matches.isEmpty || !painting.selections.isEmpty
      || painting.invisibles != nil
    let carets = needsCarets ? lineCarets : []
    for run in painting.runs {
      for rect in runRects(run.range, fullHeight: false, painting, carets: carets) {
        context.setFillColor(run.fill.cgColor)
        context.fill(rect.offsetBy(dx: point.x, dy: point.y))
      }
    }
    for match in painting.matches {
      for rect in runRects(match.range, fullHeight: false, painting, carets: carets) {
        drawMatch(rect.offsetBy(dx: point.x, dy: point.y), color: match.fill, in: context)
      }
    }
    for selection in painting.selections {
      for rect in runRects(selection.range, fullHeight: true, painting, carets: carets) {
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
    if let invisibles = painting.invisibles {
      drawInvisibles(invisibles, at: point, in: context, carets: carets)
    }
  }

  /// The rows of the fragment across the drawn span of the text view, relative to its origin.
  private func rowsBounds(_ extent: Extent) -> CGRect {
    CGRect(
      x: extent.drawnSpan.lowerBound - (super.layoutFragmentFrame.minX + extent.containerInset),
      y: 0, width: extent.drawnSpan.upperBound - extent.drawnSpan.lowerBound,
      height: CGFloat(lines.count) * rowHeight)
  }

  /// The number of screen lines that TextKit gives the text of each of the fragment's `count`
  /// rows, at least one each.
  ///
  /// A fragment lays out more than one row only before an empty last row, which TextKit gives
  /// a line of its own at the end of the paragraph.
  private func textLinesOfRows(count: Int) -> [Int] {
    var lines = Array(repeating: 0, count: count)
    for line in textLineFragments {
      lines[min(rowIndex(of: line), count - 1)] += 1
    }
    return lines.map { max($0, 1) }
  }

  /// The index among the fragment's rows of the row that `line` belongs to.
  func rowIndex(of line: NSTextLineFragment) -> Int {
    line.characterRange.lowerBound >= line.attributedString.length && rows.count > 1 ? 1 : 0
  }

  /// The rectangles of the text from offset `range.lowerBound` to `range.upperBound`, relative to
  /// the fragment's origin: one per line, as high as the text band or the whole row.
  ///
  /// A range that reaches past the end of a line includes its line feed and reaches to the right
  /// edge of the pane, as a selection of whole lines does.
  private func runRects(
    _ range: Range<Int>, fullHeight: Bool, _ painting: Painting, carets: [LineCarets]
  ) -> [CGRect] {
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
      let left = line.typographicBounds.minX + carets[lineIndex].x(at: start)
      let right =
        reachesEnd
        ? rowsBounds(painting.extent).maxX
        : line.typographicBounds.minX + carets[lineIndex].x(at: end)
      let height = fullHeight ? rowHeight : painting.textBandHeight
      let top = CGFloat(lineIndex) * rowHeight + (rowHeight - height) / 2
      return CGRect(x: left, y: top, width: right - left, height: height)
    }
  }

  /// Draws the mark of a match of the search around `rect`, the text band of its characters: a
  /// rounded outline, which tells it from the tints and the selection by its shape.
  private func drawMatch(_ rect: CGRect, color: NSColor, in context: CGContext) {
    let width = Theme.searchMatchOutlineWidth
    context.setStrokeColor(color.cgColor)
    context.setLineWidth(width)
    context.addPath(
      CGPath(
        roundedRect: rect.insetBy(dx: -width / 2, dy: -width / 2),
        cornerWidth: Theme.searchMatchCornerRadius, cornerHeight: Theme.searchMatchCornerRadius,
        transform: nil))
    context.strokePath()
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
    let lineIndex = textLineFragments.firstIndex { $0 === line } ?? 0
    return CGRect(
      x: (left + right) / 2 - width / 2,
      y: CGFloat(lineIndex) * rowHeight + (rowHeight - height) / 2, width: width, height: height)
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

  /// The screen lines that a fragment laying out `rows` takes.
  func lines(ofRows rows: Range<Int>) -> Range<Int>

  /// The rows that the fragment of the paragraph from offset `start` to `end` lays out.
  func rows(ofParagraphFrom start: Int, to end: Int) -> Range<Int>

  /// What the fragment that lays out `rows` draws now.
  func painting(forRows rows: Range<Int>) -> RowLayoutFragment.Painting
}

/// The version of a pane's text, a number that changes with every change of the text, after which
/// its fragments find their rows again.
///
/// The fragments read it each time TextKit asks for their frame, often thousands of times in a
/// row, so it is a plain box rather than a property of the pane behind the main actor. The pane
/// and its fragments use it on the main thread only.
final class TextVersion {
  private(set) var value = 0

  /// Counts a change of the text.
  func increment() {
    value += 1
  }
}

/// The line of an empty last row at the top of the row's first screen line.
private final class EmptyRowLineFragment: NSTextLineFragment {
  private let bounds: CGRect

  init(_ line: NSTextLineFragment, top: CGFloat) {
    var bounds = line.typographicBounds
    bounds.origin.y = top
    self.bounds = bounds
    super.init(attributedString: line.attributedString, range: line.characterRange)
  }

  required init?(coder: NSCoder) {
    nil
  }

  override var typographicBounds: CGRect {
    bounds
  }
}
