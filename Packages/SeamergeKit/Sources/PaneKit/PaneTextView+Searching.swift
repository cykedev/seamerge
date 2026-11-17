import AppKit

/// What a search over several panes asks of the text view of each: where a match lies on
/// screen, how the find indicator draws it, which text is in view, and replacing a match the way
/// typing would.
extension PaneTextView {
  override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    if let search, Self.isFindCommand(menuItem.action) {
      return search.validate(menuItem)
    }
    return super.validateMenuItem(menuItem)
  }

  override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
    if let search, Self.isFindCommand(item.action) {
      return search.validate(item)
    }
    return super.validateUserInterfaceItem(item)
  }

  /// Whether `action` is a command of the find bar or the Find menu.
  private static func isFindCommand(_ action: Selector?) -> Bool {
    action == #selector(performTextFinderAction(_:))
      || action == #selector(performFindPanelAction(_:))
  }

  /// The rectangles in the view of the characters of `range`, one for each screen line: as high
  /// as the row, as the selection is drawn.
  func rects(ofFoundRange range: Range<Int>) -> [CGRect] {
    guard let textLayoutManager, let textRange = textRange(of: range) else { return [] }
    textLayoutManager.ensureLayout(for: textRange)
    var rects: [CGRect] = []
    textLayoutManager.enumerateTextSegments(in: textRange, type: .standard, options: []) {
      _, frame, _, _ in
      let rect = CGRect(
        x: frame.minX + textContainerOrigin.x, y: frame.minY + textContainerOrigin.y,
        width: frame.width, height: theme.rowHeight)
      // TextKit may report a segment twice, as it does for the last line of the text.
      if rects.last != rect {
        rects.append(rect)
      }
      return true
    }
    return rects
  }

  /// Draws the characters of `range` where they stand, for the find indicator: in black, which
  /// reads on the indicator's light yellow in every appearance.
  ///
  /// Each screen line of the range is drawn on its own, on the baseline of its row.
  func drawFoundCharacters(in range: Range<Int>) {
    guard let textLayoutManager, let textRange = textRange(of: range) else { return }
    textLayoutManager.ensureLayout(for: textRange)
    let documentStart = textLayoutManager.documentRange.location
    var attributes = textAttributes
    attributes[.foregroundColor] = NSColor.black
    let text = string as NSString
    var drawn: [CGRect] = []
    textLayoutManager.enumerateTextSegments(in: textRange, type: .standard, options: []) {
      segment, frame, _, _ in
      guard let segment, !drawn.contains(frame) else { return true }
      drawn.append(frame)
      let start = textLayoutManager.offset(from: documentStart, to: segment.location)
      let end = textLayoutManager.offset(from: documentStart, to: segment.endLocation)
      guard start < end else { return true }
      let piece = text.substring(with: NSRange(location: start, length: end - start))
      NSAttributedString(string: piece, attributes: attributes).draw(
        at: CGPoint(
          x: frame.minX + textContainerOrigin.x,
          y: frame.minY + textContainerOrigin.y + theme.baseline - theme.font.ascender))
      return true
    }
  }

  /// The range of the text that the rows in view hold, collapsed runs and all.
  var visibleTextRange: Range<Int> {
    let visible = visibleRect
    guard !visible.isEmpty else { return 0..<0 }
    let first = displayRows.row(
      atDisplayRow: displayRows.clampedDisplayRow(
        atLine: Int((visible.minY / theme.rowHeight).rounded(.down))))
    let last = displayRows.row(
      atDisplayRow: displayRows.clampedDisplayRow(
        atLine: Int((visible.maxY / theme.rowHeight).rounded(.up))))
    return grid.paragraphOffsets(ofRows: first..<max(last, first) + 1)
  }

  /// Replaces a match as typing would: the editing delegate decides how, the pane carries out
  /// its answer and reports it.
  ///
  /// A replacement may change text behind a collapsed run: the user asked for it, and a single
  /// match has been brought into view by then.
  func replaceFoundText(_ edit: PaneEdit) {
    guard isEditable, let interaction, edit.range.upperBound <= grid.textLength else { return }
    let plan = interaction.edits(for: edit)
    guard !plan.isEmpty else { return }
    let replacedTexts = carryOut(plan)
    interaction.didCarryOut(plan, replacing: replacedTexts)
  }

  /// Draws the rows that `range` of the text touches again.
  func redraw(range: Range<Int>) {
    let start = grid.row(containingOffset: min(range.lowerBound, grid.textLength))
    let end = grid.row(containingOffset: min(range.upperBound, grid.textLength))
    redraw(rows: start..<end + 1)
  }

  /// The matches of the search within the paragraph of `paragraph`, with their fill.
  func searchMatchRuns(in paragraph: Range<Int>) -> [RowLayoutFragment.Run] {
    guard !searchMatches.isEmpty else { return [] }
    let fill = theme.searchMatchColor
    var index = searchMatches.partitioningIndex { $0.upperBound > paragraph.lowerBound }
    var runs: [RowLayoutFragment.Run] = []
    while index < searchMatches.count, searchMatches[index].lowerBound < paragraph.upperBound {
      runs.append(RowLayoutFragment.Run(range: searchMatches[index], fill: fill))
      index += 1
    }
    return runs
  }

  /// The range of TextKit of `range` of the text, or `nil` if it reaches beyond the text.
  private func textRange(of range: Range<Int>) -> NSTextRange? {
    guard let textLayoutManager, range.upperBound <= grid.textLength else { return nil }
    let documentStart = textLayoutManager.documentRange.location
    guard
      let start = textLayoutManager.location(documentStart, offsetBy: range.lowerBound),
      let end = textLayoutManager.location(documentStart, offsetBy: range.upperBound)
    else { return nil }
    return NSTextRange(location: start, end: end)
  }
}
