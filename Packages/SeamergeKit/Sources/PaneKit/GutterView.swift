import AppKit

/// The left margin of a pane: the line numbers, the markers of the blocks and the filled cells of
/// the current block.
///
/// The gutter sits beside the scroll view and draws the visible rows itself, each at its display
/// row times the row height, minus the scroll offset of the text. The bars of collapsed runs
/// cover their rows across the gutter; it leaves them empty. While the pointer is over the rows
/// of a run that the user expanded, a quiet sign beside its first row collapses it again.
final class GutterView: NSView {
  var theme = Theme() {
    didSet {
      numberColumnWidth = Self.numberColumnWidth(of: content, theme: theme)
      needsDisplay = true
      updateToolTips()
    }
  }

  var content = PaneContent.empty {
    didSet {
      numberColumnWidth = Self.numberColumnWidth(of: content, theme: theme)
      needsDisplay = true
      updateToolTips()
      // Runs beyond the rows of new content cannot be shown until the owner hands new ones.
      let rowCount = content.lineNumbers.count
      if expandedRuns.contains(where: { $0.rows.upperBound > rowCount }) {
        expandedRuns = expandedRuns.filter { $0.rows.upperBound <= rowCount }
      }
    }
  }

  /// The width of the column of line numbers, which only the content and the theme change.
  private var numberColumnWidth = GutterView.numberColumnWidth(of: .empty, theme: Theme())

  var currentBlock: Int? {
    didSet { needsDisplay = true }
  }

  /// The rows as the pane shows them, with collapsed runs.
  var displayRows = DisplayRows(runs: [], rowCount: 1) {
    didSet {
      needsDisplay = true
      updateToolTips()
    }
  }

  /// The vertical scroll offset of the text beside the gutter.
  var scrollOffset: CGFloat = 0 {
    didSet {
      needsDisplay = true
      if scrollOffset != oldValue {
        followPointer()
        updateToolTips()
      }
    }
  }

  /// The runs that the user expanded and that may collapse again, in rows of the content.
  var expandedRuns: [CollapsedRun] = [] {
    didSet {
      guard expandedRuns != oldValue else { return }
      needsDisplay = true
      followPointer()
      updateToolTips()
    }
  }

  /// The index in ``expandedRuns`` of the run whose rows the pointer is over, whose sign shows.
  private(set) var hoveredRun: Int? {
    didSet {
      if hoveredRun != oldValue {
        needsDisplay = true
        updateToolTips()
      }
    }
  }

  /// The rows among the given ones that hold marks of removed text, which the text draws and
  /// the gutter names for VoiceOver.
  var removalRows: (Range<Int>) -> [Int] = { _ in [] }

  /// Whether the pane has the focus in the key window, which the text knows; the cells of the
  /// current block then show in the accent color, as a focused selection does.
  var hasFocus: () -> Bool = { false }

  /// The rows that are visible beside the text, without those behind bars.
  var visibleRows: [Int] {
    rows(in: bounds)
  }

  /// The rows that `rect` of the gutter shows, without those behind bars.
  func rows(in rect: CGRect) -> [Int] {
    let rowHeight = theme.rowHeight
    let firstLine = max(Int(((rect.minY + scrollOffset) / rowHeight).rounded(.down)), 0)
    let endLine = Int(((rect.maxY + scrollOffset) / rowHeight).rounded(.up))
    let first = min(displayRows.displayRow(atLine: firstLine), displayRows.count)
    let end =
      endLine > firstLine
      ? min(displayRows.displayRow(atLine: endLine - 1) + 1, displayRows.count) : first
    return (first..<max(first, end)).compactMap { displayRow in
      displayRows.runIndex(atDisplayRow: displayRow) == nil
        ? displayRows.row(atDisplayRow: displayRow) : nil
    }
  }

  /// The rectangle of `row` across the gutter, all of its screen lines.
  func rect(ofRow row: Int) -> CGRect {
    let lines = displayRows.lines(ofRows: row..<row + 1)
    return CGRect(
      x: 0, y: CGFloat(lines.lowerBound) * theme.rowHeight - scrollOffset,
      width: bounds.width, height: CGFloat(lines.count) * theme.rowHeight)
  }

  /// The slot of the marker `index` places from the trailing edge beside the first screen line
  /// of the row of `rowRect`.
  func markerSlot(_ index: Int, in rowRect: CGRect) -> CGRect {
    CGRect(
      x: bounds.width - CGFloat(index + 1) * Theme.markerSlotWidth, y: rowRect.minY,
      width: Theme.markerSlotWidth, height: min(rowRect.height, theme.rowHeight))
  }

  override var isFlipped: Bool { true }

  /// Learns about clicks on rows and supplies the context menu.
  weak var interaction: (any RowInteraction)?

  override func setFrameSize(_ newSize: NSSize) {
    let changed = newSize != frame.size
    super.setFrameSize(newSize)
    if changed {
      updateToolTips()
    }
  }

  /// Gives the marks their help tags again in the new window, which keeps the areas of tags.
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    updateToolTips()
  }

  /// The marks beside `row` from the trailing edge on, each with what it means: the mark of how
  /// a side changed the block and the mark of a conflict before it at the first row of a block,
  /// and on a row without either the ring of an ignored difference.
  func marks(ofRow row: Int) -> [(mark: GutterMark, help: String)] {
    var marks: [(mark: GutterMark, help: String)] = []
    if let blockIndex = content.blockIndex(atRow: row),
      content.blocks[blockIndex].rows.lowerBound == row
    {
      let block = content.blocks[blockIndex]
      if let marker = block.marker {
        marks.append((.marker(marker, block.style), MarkHelp.marker(marker)))
      }
      if let conflict = block.conflict {
        marks.append((.conflict(conflict), MarkHelp.conflict(conflict)))
      }
    }
    if marks.isEmpty && content.ignoredDifferenceRows.contains(row) {
      marks.append((.ignoredDifference, MarkHelp.ignoredDifference))
    }
    return marks
  }

  /// Gives each mark in view, and the sign that collapses a run, an area of its own for a help
  /// tag, whose text ``view(_:stringForToolTip:point:userData:)`` finds.
  private func updateToolTips() {
    removeAllToolTips()
    for row in visibleRows {
      let rowRect = rect(ofRow: row)
      for index in marks(ofRow: row).indices {
        addToolTip(markerSlot(index, in: rowRect), owner: self, userData: nil)
      }
    }
    if let hoveredRun {
      addToolTip(collapseSignRect(ofRun: hoveredRun), owner: self, userData: nil)
    }
  }

  /// Gives the pane the focus, then collapses the run whose sign is clicked, or else tells which
  /// row the click is beside.
  override func mouseDown(with event: NSEvent) {
    interaction?.takeFocus()
    let point = convert(event.locationInWindow, from: nil)
    if let index = expandedRuns.indices.first(where: {
      isShowingCollapseSign(ofRun: $0) && collapseSignRect(ofRun: $0).contains(point)
    }) {
      interaction?.askToCollapse(expandedRuns[index])
      return
    }
    interaction?.rowWasClicked(row(at: point))
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    // Only the area of the pointer: the help tags have areas of their own.
    if let pointerArea {
      removeTrackingArea(pointerArea)
    }
    let area = NSTrackingArea(
      rect: .zero,
      options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
      owner: self)
    addTrackingArea(area)
    pointerArea = area
  }

  /// The area that follows the pointer over the gutter.
  private var pointerArea: NSTrackingArea?

  override func mouseEntered(with event: NSEvent) {
    pointerMoved(to: convert(event.locationInWindow, from: nil))
  }

  override func mouseMoved(with event: NSEvent) {
    pointerMoved(to: convert(event.locationInWindow, from: nil))
  }

  override func mouseExited(with event: NSEvent) {
    hoveredRun = nil
  }

  /// Shows the sign of the expanded run whose rows lie at `point`, if any.
  func pointerMoved(to point: CGPoint) {
    guard bounds.contains(point), !expandedRuns.isEmpty else {
      hoveredRun = nil
      return
    }
    let line = Int(((point.y + scrollOffset) / theme.rowHeight).rounded(.down))
    let displayRow = line >= 0 ? displayRows.displayRow(atLine: line) : -1
    guard displayRow >= 0, displayRow < displayRows.count,
      displayRows.runIndex(atDisplayRow: displayRow) == nil
    else {
      hoveredRun = nil
      return
    }
    let row = displayRows.row(atDisplayRow: displayRow)
    hoveredRun = expandedRuns.firstIndex { $0.rows.contains(row) }
  }

  /// Follows the pointer after the rows moved under it.
  private func followPointer() {
    guard let window, hoveredRun != nil || !expandedRuns.isEmpty else { return }
    pointerMoved(to: convert(window.mouseLocationOutsideOfEventStream, from: nil))
  }

  /// Whether the sign that collapses the expanded run at `index` shows: while the pointer is
  /// over the run's rows.
  func isShowingCollapseSign(ofRun index: Int) -> Bool {
    hoveredRun == index
  }

  /// Where the sign that collapses the expanded run at `index` lies: in the slot of the markers
  /// beside the run's first row, as large as the smallest target of a click.
  func collapseSignRect(ofRun index: Int) -> CGRect {
    let slot = markerSlot(0, in: rect(ofRow: expandedRuns[index].rows.lowerBound))
    let size = max(Theme.markerSlotWidth, Theme.decisionControlSize)
    let height = max(slot.height, Theme.decisionControlSize)
    return CGRect(x: bounds.width - size, y: slot.midY - height / 2, width: size, height: height)
  }

  override func menu(for event: NSEvent) -> NSMenu? {
    guard let interaction, interaction.suppliesMenus else { return super.menu(for: event) }
    return interaction.menu(forRow: row(at: convert(event.locationInWindow, from: nil)))
  }

  /// The row at `point` of the gutter, the nearest one beyond the text.
  private func row(at point: CGPoint) -> Int {
    let line = Int(((point.y + scrollOffset) / theme.rowHeight).rounded(.down))
    return displayRows.row(atDisplayRow: displayRows.clampedDisplayRow(atLine: line))
  }

  /// The width that the gutter needs for the widest line number and the markers of `content`.
  var fittingWidth: CGFloat {
    let width =
      Theme.gutterLeadingInset + numberColumnWidth + Theme.gutterNumberSpacing
      + CGFloat(markerSlotCount) * Theme.markerSlotWidth
    return (width / Theme.layoutGrid).rounded(.up) * Theme.layoutGrid
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    // Views draw beyond their bounds unless told otherwise, and the dirty rectangle may reach
    // past them.
    clipsToBounds = true
  }

  /// Gutters are never archived.
  required init?(coder: NSCoder) {
    nil
  }

  override func draw(_ dirtyRect: NSRect) {
    defer { drawCollapseSign(in: dirtyRect) }
    let dirtyRect = dirtyRect.intersection(bounds)
    Theme.backgroundColor.setFill()
    dirtyRect.fill()
    let rows = rows(in: dirtyRect)
    let hasFocus = hasFocus()
    let numberAttributes = lineNumberAttributes(color: theme.lineNumberColor)
    let currentColor = Theme.currentCellContentColor(isEmphasized: hasFocus)
    let currentNumberAttributes = lineNumberAttributes(color: currentColor)
    for row in rows {
      let rowRect = rect(ofRow: row)
      let blockIndex = content.blockIndex(atRow: row)
      let isCurrent = blockIndex != nil && blockIndex == currentBlock
      if isCurrent {
        Theme.currentCellFill(isEmphasized: hasFocus).setFill()
        rowRect.fill()
      }
      let lineNumber = content.lineNumbers[row]
      if lineNumber >= 0 {
        drawLineNumber(
          Int(lineNumber) + 1, in: rowRect,
          attributes: isCurrent ? currentNumberAttributes : numberAttributes)
      }
      drawMarkers(ofRow: row, in: rowRect, color: isCurrent ? currentColor : nil)
    }
  }

  /// The width of the widest line number of `content`, with room for a few digits at least.
  private static func numberColumnWidth(of content: PaneContent, theme: Theme) -> CGFloat {
    let largest = content.lineNumbers.max().map { Int($0) + 1 } ?? 0
    let digits = max(String(largest).count, Theme.minimumLineNumberDigits)
    let digitWidth = ("0" as NSString).size(withAttributes: [.font: theme.lineNumberFont]).width
    return CGFloat(digits) * digitWidth
  }

  /// The number of markers that the busiest row of `content` shows side by side, at least one.
  private var markerSlotCount: Int {
    content.blocks.reduce(1) { count, block in
      max(count, (block.marker == nil ? 0 : 1) + (block.conflict == nil ? 0 : 1))
    }
  }

  private func lineNumberAttributes(color: NSColor) -> [NSAttributedString.Key: Any] {
    [.font: theme.lineNumberFont, .foregroundColor: color]
  }

  private func drawLineNumber(
    _ number: Int, in rowRect: CGRect, attributes: [NSAttributedString.Key: Any]
  ) {
    let text = String(number) as NSString
    let size = text.size(withAttributes: attributes)
    let font = attributes[.font] as? NSFont ?? theme.lineNumberFont
    // Shares the baseline of the code beside it.
    let origin = CGPoint(
      x: Theme.gutterLeadingInset + numberColumnWidth - size.width,
      y: rowRect.minY + theme.baseline - font.ascender)
    text.draw(at: origin, withAttributes: attributes)
  }

  /// Draws the marks of `row` right-aligned in their slots, as ``marks(ofRow:)`` lists them.
  ///
  /// - Parameter color: The color of every mark on a filled cell of the current block, which
  ///   takes the color of selected content as the line number does; `nil` on a plain cell, where
  ///   each mark has its own color.
  private func drawMarkers(ofRow row: Int, in rowRect: CGRect, color: NSColor?) {
    for (index, entry) in marks(ofRow: row).enumerated() {
      let slot = markerSlot(index, in: rowRect)
      switch entry.mark {
      case .marker(let marker, let style):
        drawCharacter(
          Self.character(for: marker), color: color ?? theme.markerColor(for: style),
          centeredIn: slot, withSeam: color == nil)
      case .conflict(let conflict):
        drawCharacter(
          Self.conflictCharacter, color: color ?? theme.color(for: conflict), centeredIn: slot,
          withSeam: color == nil)
      case .ignoredDifference:
        drawRing(centeredIn: slot, color: color)
      }
    }
  }

  /// Draws a typed mark in the code font, on the baseline of the code beside it, within a seam of
  /// background color if `withSeam`.
  ///
  /// The seam cannot be seen on the plain gutter; it keeps a mark in its own color as clear as
  /// there wherever a fill lies behind it.
  private func drawCharacter(
    _ character: String, color: NSColor, centeredIn slot: CGRect, withSeam: Bool
  ) {
    let text = NSAttributedString(
      string: character, attributes: [.font: theme.font, .foregroundColor: color])
    let origin = pixelAligned(
      CGPoint(
        x: slot.midX - text.size().width / 2, y: slot.minY + theme.baseline - theme.font.ascender))
    if withSeam {
      // The stroke is centered on the outline of the glyph, so half of it lies outside.
      let strokeWidth = 2 * Theme.markSeam / theme.font.pointSize * 100
      NSAttributedString(
        string: character,
        attributes: [
          .font: theme.font, .strokeColor: Theme.backgroundColor, .strokeWidth: strokeWidth,
        ]
      ).draw(at: origin)
    }
    text.draw(at: origin)
  }

  /// Draws the hollow ring of a line whose difference the comparison ignores, in `color` or, on a
  /// plain cell, in the secondary color within a seam of background color like the typed marks.
  private func drawRing(centeredIn slot: CGRect, color: NSColor?) {
    let ring = NSImage(systemSymbolName: "circle", accessibilityDescription: nil)
    guard
      let image = ring?.withSymbolConfiguration(
        theme.ringSymbolConfiguration.applying(
          NSImage.SymbolConfiguration(paletteColors: [color ?? Theme.secondaryMarkColor]))),
      let seam = ring?.withSymbolConfiguration(
        theme.ringSymbolConfiguration.applying(
          NSImage.SymbolConfiguration(paletteColors: [Theme.backgroundColor])))
    else { return }
    let size = image.size
    let rect = CGRect(
      origin: pixelAligned(CGPoint(x: slot.midX - size.width / 2, y: slot.midY - size.height / 2)),
      size: size)
    // The ring drawn once more, a seam wider on either side, lies below it; a ring in the color
    // of selected content stands on a filled cell and needs none.
    if color == nil {
      for inset in [-Theme.markSeam, 0, Theme.markSeam] {
        seam.draw(in: rect.insetBy(dx: inset, dy: inset))
      }
    }
    image.draw(in: rect)
  }

  /// Draws the sign that collapses the expanded run under the pointer beside its first row, in
  /// the color of the line numbers like the bar of a collapsed run, in place of a ring that may
  /// stand there.
  private func drawCollapseSign(in dirtyRect: CGRect) {
    guard let hoveredRun else { return }
    let signRect = collapseSignRect(ofRun: hoveredRun)
    let rowRect = rect(ofRow: expandedRuns[hoveredRun].rows.lowerBound)
    guard signRect.intersects(dirtyRect), bounds.intersects(rowRect),
      let symbol = NSImage(
        systemSymbolName: "arrow.down.and.line.horizontal.and.arrow.up",
        accessibilityDescription: nil)?
        .withSymbolConfiguration(
          NSImage.SymbolConfiguration(pointSize: theme.lineNumberFont.pointSize, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [theme.lineNumberColor])))
    else { return }
    let slot = markerSlot(0, in: rowRect)
    Theme.backgroundColor.setFill()
    slot.fill()
    let size = symbol.size
    let origin = CGPoint(x: slot.midX - size.width / 2, y: slot.midY - size.height / 2)
    symbol.draw(in: CGRect(origin: pixelAligned(origin), size: size))
  }

  /// `point` moved to the nearest pixel of the screen, so that thin marks stay sharp.
  private func pixelAligned(_ point: CGPoint) -> CGPoint {
    let backing = convertToBacking(point)
    return convertFromBacking(CGPoint(x: backing.x.rounded(), y: backing.y.rounded()))
  }

  /// The typed mark of how a side changed a block.
  private static func character(for marker: Marker) -> String {
    switch marker {
    case .added: "+"
    case .changed: "~"
    case .removed: "\u{2212}"
    }
  }

  /// The typed mark of a conflict.
  private static let conflictCharacter = "!"
}

/// A mark in the gutter.
enum GutterMark {
  /// How a side changed a block, in the color of its style.
  case marker(Marker, BlockStyle)
  /// A conflict, open or resolved.
  case conflict(ConflictMarker)
  /// The hollow ring of a line whose difference the comparison ignores, drawn as a symbol.
  case ignoredDifference
}

extension GutterView: NSViewToolTipOwner {
  /// What the mark at `point` means, or what the sign that collapses a run there does.
  func view(
    _ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint,
    userData data: UnsafeMutableRawPointer?
  ) -> String {
    if let hoveredRun, collapseSignRect(ofRun: hoveredRun).contains(point) {
      return MarkHelp.collapseRun
    }
    let row = row(at: point)
    let rowRect = rect(ofRow: row)
    return marks(ofRow: row).enumerated().first {
      markerSlot($0.offset, in: rowRect).contains(point)
    }?.element.help ?? ""
  }
}
