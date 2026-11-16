import AppKit
import MergeModel
import PaneKit

/// The single column of a comparison: its content, how its rows relate to the grid, and the
/// switch between it and the panes side by side.
///
/// A row of the column shows a line of a file, and that line lies on a row of the grid; so the
/// column converts to the grid through the lines it shows, and the commands that work on the
/// grid, such as collapsing, Go to Line and the place at the reading line, work on the column
/// through ``gridRow(ofRow:in:)`` and ``row(ofGridRow:in:)``.
extension SessionPresentation {
  /// How the panes lay out the lines of the files now.
  var lineArrangement: LineArrangement {
    LineArrangement(alignsLines: alignsLines, showsSingleColumn: columnLayout != nil)
  }

  /// Whether the window can show its files in a single column: a comparison of two files can,
  /// a merge cannot.
  var canShowSingleColumn: Bool {
    layout.columnPane != nil
  }

  /// Shows both files in a single column, or the panes side by side again: a change of what the
  /// window shows, which the user cannot undo and need not.
  ///
  /// The current block, the block at the reading line and the selection stay, as far as the
  /// selection exists in both: the selection of the pane side by side that has the focus becomes
  /// that of the column, and a selection within the lines of one side of the column becomes that
  /// of its pane. The panes side by side keep whether they line up their lines.
  ///
  /// - Returns: The pane that shows what the pane with the focus showed, which takes the focus
  ///   if that pane had it: the column, or else the pane side by side of the selection, or the
  ///   one on the left.
  /// - Precondition: The window can show a single column, if it is to show it.
  @discardableResult
  func setShowsSingleColumn(_ shows: Bool) -> PaneView? {
    guard shows != (columnLayout != nil), let columnPane = layout.columnPane else {
      precondition(!shows || canShowSingleColumn, "Only a comparison shows a single column")
      return nil
    }
    return shows ? showSingleColumn(in: columnPane) : showPanesSideBySide(from: columnPane)
  }

  /// Puts the single column in place of the panes side by side.
  private func showSingleColumn(in columnPane: PaneView) -> PaneView {
    let place = gridPlaceAtReadingLine
    let selection = layout.sourcePanes.first { $0.pane.holdsFocus }.map { role, pane in
      (
        role: role,
        ranges: pane.documentView.selectedRanges.map { textRange($0.rangeValue, in: role) }
      )
    }
    let column = SingleColumnLayout(session: changes.session, firstSide: arrangement.leadingRole)
    columnLayout = column
    layout.showsSingleColumn = true
    showColumnContent()
    updateSearchSections()
    if let (role, ranges) = selection {
      columnPane.documentView.selectedRanges = ranges.map { range in
        NSValue(range: columnRange(from: range.start, to: range.end, in: role, of: column))
      }
    }
    layout.view.layoutSubtreeIfNeeded()
    if let place {
      let row = columnRow(ofGridPlace: place, in: column)
      columnPane.scroll(
        toPlaceRowAtReadingLine: row.row, fraction: row.fraction, motion: .cut)
    }
    return columnPane
  }

  /// Puts the panes side by side in place of the single column.
  private func showPanesSideBySide(from columnPane: PaneView) -> PaneView? {
    guard let column = columnLayout else { return nil }
    let (row, fraction) = columnPane.rowAtReadingLine
    let place =
      column.rowCount > 0
      ? Double(gridRow(ofColumnRow: row, in: column)) + Double(fraction) : nil
    let selection = sideSelection(of: columnPane, in: column)
    columnLayout = nil
    columnSyntax = nil
    columnHighlights = nil
    layout.showsSingleColumn = false
    layout.view.layoutSubtreeIfNeeded()
    updateSearchSections()
    if let place {
      scroll(toGridPlace: place)
    }
    if let (role, ranges) = selection, let pane = layout.sourcePane(role) {
      pane.documentView.selectedRanges = ranges.map { NSValue(range: paneRange($0, in: role)) }
      return pane
    }
    return layout.sourcePanes.first?.pane
  }

  /// Lays out the single column anew, while it shows, from the session as it is now and with
  /// the sides in the order of the panes, and gives it its content.
  func showColumn() {
    guard columnLayout != nil else { return }
    columnLayout = SingleColumnLayout(session: changes.session, firstSide: arrangement.leadingRole)
    showColumnContent()
  }

  /// Gives the single column its content, its collapsed runs, its marks and its tokens.
  private func showColumnContent() {
    guard let column = columnLayout else { return }
    showColumn(
      PreparedSession.column(
        column, changes: changes, collapsed: collapsed,
        ignoredDifferences: ignoredDifferences ?? IgnoredDifferences(in: changes.session),
        showsIgnoredPlaces: showsIgnoredChanges, lines: &lines))
  }

  /// Gives the single column what `prepared` holds for it, the runs the user expanded, the
  /// current block and its tokens.
  func showColumn(_ prepared: PreparedSession.Column) {
    guard let pane = layout.columnPane else { return }
    let column = prepared.layout
    columnLayout = column
    let highlights = BlockHighlights(changes: changes, rows: .column(column))
    columnHighlights = highlights
    pane.highlightProvider = highlights
    if let preparedContent = prepared.prepared {
      pane.setContent(preparedContent, collapsedRuns: prepared.collapsedRuns)
    } else {
      pane.setContent(prepared.content, collapsedRuns: prepared.collapsedRuns)
    }
    pane.expandedRuns = columnRuns(of: collapsed.expandedRuns, in: column)
    pane.currentBlock = currentBlock
    columnOverviewBar?.marks = prepared.marks
    columnOverviewBar?.currentBlock = currentBlock
    // The tokens of a former layout name its rows.
    columnSyntax = nil
    pane.syntaxProvider = nil
    showColumnSyntax()
  }

  /// Gives the single column, while it shows, the runs that are collapsed now.
  func showColumnRuns() {
    guard let column = columnLayout, let pane = layout.columnPane else { return }
    pane.collapsedRuns = columnRuns(of: collapsed.runs, in: column)
    pane.expandedRuns = columnRuns(of: collapsed.expandedRuns, in: column)
  }

  /// `runs` in the rows of `column`.
  private func columnRuns(
    of runs: [CollapsedRows.Run], in column: SingleColumnLayout
  ) -> [CollapsedRun] {
    PreparedSession.columnRuns(of: runs, in: column, collapsed: collapsed)
  }

  /// Gives the single column, while it shows, the tokens of both files as far as they are
  /// known, unless it has them already.
  func showColumnSyntax() {
    guard let column = columnLayout, let pane = layout.columnPane else { return }
    let (a, b) = (syntax.tokens(of: .a), syntax.tokens(of: .b))
    if let columnSyntax, columnSyntax.a === a, columnSyntax.b === b { return }
    let tokens = a == nil && b == nil ? nil : ColumnSyntaxTokens(column: column, a: a, b: b)
    columnSyntax = tokens
    pane.syntaxProvider = tokens
  }

  /// The row of the grid that shows the line that `row` of `column` shows: the line of its side,
  /// or of the first side for a line both share, which lies on the same row of the grid.
  func gridRow(ofColumnRow row: Int, in column: SingleColumnLayout) -> Int {
    let place = column.place(atRow: row)
    let side = place.side ?? column.firstSide
    guard let line = place.line(in: side) else {
      preconditionFailure("Every row of a single column shows a line")
    }
    return changes.session.rowLayout.row(ofLine: line, in: side)
  }

  /// The row of `column` at `gridRow`: in the same block, the line at the same place among the
  /// lines of the first side, or else among those of the second.
  func columnRow(ofGridRow gridRow: Int, in column: SingleColumnLayout) -> Int {
    let rowLayout = changes.session.rowLayout
    guard rowLayout.rowCount > 0, column.rowCount > 0 else { return 0 }
    let block = rowLayout.block(atRow: min(max(gridRow, 0), rowLayout.rowCount - 1))
    let offset = gridRow - rowLayout.rows(of: block).lowerBound
    for side in [column.firstSide, PaneContent.otherSide(of: column.firstSide)] {
      let lines = block.lines(in: side)
      if offset < lines.count {
        return column.row(ofLine: lines.lowerBound + offset, in: side)
      }
    }
    return min(column.rows(of: block).lowerBound, column.rowCount - 1)
  }

  /// The row of `column` and the fraction of it at `place`, a row of the grid with its fraction.
  private func columnRow(
    ofGridPlace place: Double, in column: SingleColumnLayout
  ) -> (row: Int, fraction: CGFloat) {
    let gridRow = Int(place.rounded(.down))
    return (columnRow(ofGridRow: gridRow, in: column), CGFloat(place - Double(gridRow)))
  }

  /// The range of the text of `column` from `start` to `end`, places in the lines of `role`.
  private func columnRange(
    from start: TextPlace, to end: TextPlace, in role: Role, of column: SingleColumnLayout
  ) -> NSRange {
    let lineCount = changes.session.rowLayout.lineCount(in: role)
    func offset(of place: TextPlace) -> Int {
      guard lineCount > 0, column.rowCount > 0 else { return 0 }
      guard place.line < lineCount else {
        return column.displayText.utf16Range(ofRow: column.rowCount - 1).upperBound
      }
      let range = column.displayText.utf16Range(ofRow: column.row(ofLine: place.line, in: role))
      return range.lowerBound + min(place.column, range.count)
    }
    let (lower, upper) = (offset(of: start), offset(of: end))
    return NSRange(location: lower, length: max(upper - lower, 0))
  }

  /// The selection of `columnPane` as places in the lines of one side, with that side: of the
  /// side whose lines it touches, or of the second side, whose text a shared row shows, if it
  /// touches only rows both share; `nil` if it touches the lines of both sides.
  private func sideSelection(
    of columnPane: PaneView, in column: SingleColumnLayout
  ) -> (role: Role, ranges: [(start: TextPlace, end: TextPlace)])? {
    guard column.rowCount > 0 else { return nil }
    func rowStart(_ row: Int) -> Int { columnPane.textRange(ofRows: row..<row + 1).location }
    var sides = Set<Role>()
    var places: [(start: (row: Int, column: Int), end: (row: Int, column: Int))] = []
    for value in columnPane.documentView.selectedRanges {
      let range = value.rangeValue
      let start = columnPane.row(containingOffset: range.location)
      let end = columnPane.row(containingOffset: range.location + range.length)
      for row in [start, end] {
        if let side = column.place(atRow: row).side {
          sides.insert(side)
        }
      }
      places.append(
        (
          (start, range.location - rowStart(start)),
          (end, range.location + range.length - rowStart(end))
        ))
    }
    guard sides.count <= 1 else { return nil }
    let role = sides.first ?? PaneContent.otherSide(of: column.firstSide)
    func textPlace(_ place: (row: Int, column: Int)) -> TextPlace {
      TextPlace(line: column.place(atRow: place.row).line(in: role) ?? 0, column: place.column)
    }
    return (role, places.map { (textPlace($0.start), textPlace($0.end)) })
  }
}
