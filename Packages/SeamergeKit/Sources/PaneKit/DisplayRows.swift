/// The rows of a pane as it shows them: every row of its grid, except that each collapsed run
/// takes a single *display row*, the row of its bar.
///
/// Each display row takes one or more *screen lines*, each a row height high: a row that wraps
/// takes as many as its most wrapped version in the panes it lines up with, a bar takes one.
/// Display row *d* lies at its first screen line times the row height from the top of the text.
/// Positions may be fractional, so that coupled panes can match a place within a bar or a
/// wrapped row too: a bar spans its hidden rows evenly, and a row spreads over its lines.
struct DisplayRows {
  /// The collapsed runs, in row order.
  let runs: [CollapsedRun]

  /// The number of rows of the grid.
  let rowCount: Int

  /// The rows of the grid that take more than one screen line.
  let wrappedRows: WrappedRows

  /// The display row of the bar of each run, followed by the number of display rows.
  private let barRows: [Int]

  /// The display rows that take more than one screen line, in order.
  private let tallRows: [TallRow]

  /// Collapses `runs` of a grid with `rowCount` rows, whose rows take as many screen lines as
  /// `wrappedRows` says; a row behind a bar takes none, and the bar one.
  ///
  /// - Precondition: The runs are sorted, do not overlap and lie within the rows.
  init(runs: [CollapsedRun], rowCount: Int, wrappedRows: WrappedRows = .none) {
    var barRows: [Int] = []
    barRows.reserveCapacity(runs.count + 1)
    var hiddenRows = 0
    var end = 0
    for run in runs {
      precondition(
        run.rows.lowerBound >= end && run.rows.upperBound <= rowCount,
        "Collapsed rows \(run.rows) overlap others or lie beyond the \(rowCount) rows")
      barRows.append(run.rows.lowerBound - hiddenRows)
      hiddenRows += run.rows.count - 1
      end = run.rows.upperBound
    }
    barRows.append(rowCount - hiddenRows)
    self.runs = runs
    self.rowCount = rowCount
    self.barRows = barRows
    let wrappedRows = wrappedRows.clamped(toRowCount: rowCount)
    self.wrappedRows = wrappedRows
    var tallRows: [TallRow] = []
    tallRows.reserveCapacity(wrappedRows.entries.count)
    var extraLines = 0
    for entry in wrappedRows.entries {
      guard !Self.isCollapsed(row: entry.row, runs: runs) else { continue }
      let displayRow = Self.displayRow(ofRow: entry.row, runs: runs, barRows: barRows)
      tallRows.append(
        TallRow(displayRow: displayRow, firstLine: displayRow + extraLines, lines: entry.lines))
      extraLines += entry.lines - 1
    }
    self.tallRows = tallRows
  }

  /// A display row that takes more than one screen line.
  private struct TallRow {
    var displayRow: Int
    var firstLine: Int
    var lines: Int
  }

  /// The number of display rows.
  var count: Int { barRows[barRows.count - 1] }

  /// The display row that shows `row`: its own, or the bar of the run that hides it.
  func displayRow(ofRow row: Int) -> Int {
    Self.displayRow(ofRow: row, runs: runs, barRows: barRows)
  }

  private static func displayRow(ofRow row: Int, runs: [CollapsedRun], barRows: [Int]) -> Int {
    let index = runs.partitioningIndex { $0.rows.lowerBound > row } - 1
    guard index >= 0 else { return row }
    let run = runs[index]
    return run.rows.contains(row) ? barRows[index] : barRows[index] + 1 + row - run.rows.upperBound
  }

  private static func isCollapsed(row: Int, runs: [CollapsedRun]) -> Bool {
    let index = runs.partitioningIndex { $0.rows.lowerBound > row } - 1
    return index >= 0 && runs[index].rows.contains(row)
  }

  /// The display rows that show `rows`.
  func displayRows(ofRows rows: Range<Int>) -> Range<Int> {
    guard !rows.isEmpty else {
      let row = rows.lowerBound < rowCount ? displayRow(ofRow: rows.lowerBound) : count
      return row..<row
    }
    return displayRow(ofRow: rows.lowerBound)..<displayRow(ofRow: rows.upperBound - 1) + 1
  }

  /// The row that `displayRow` shows, or the first row that its bar hides.
  func row(atDisplayRow displayRow: Int) -> Int {
    guard let index = lastIndex(where: { barRows[$0] <= displayRow }) else { return displayRow }
    let barRow = barRows[index]
    return barRow == displayRow
      ? runs[index].rows.lowerBound : runs[index].rows.upperBound + displayRow - barRow - 1
  }

  /// The index of the run whose bar is `displayRow`, if any.
  func runIndex(atDisplayRow displayRow: Int) -> Int? {
    guard let index = lastIndex(where: { barRows[$0] <= displayRow }) else { return nil }
    return barRows[index] == displayRow ? index : nil
  }

  /// The index of the run that hides `row`, if any.
  func runIndex(containingRow row: Int) -> Int? {
    guard let index = lastRun(where: { $0.rows.lowerBound <= row }) else { return nil }
    return runs[index].rows.contains(row) ? index : nil
  }

  /// The indices of the runs whose bars lie in `displayRange`.
  func runIndices(withBarsIn displayRange: Range<Int>) -> Range<Int> {
    let first = lastIndex { barRows[$0] < displayRange.lowerBound }.map { $0 + 1 } ?? 0
    let end = lastIndex { barRows[$0] < displayRange.upperBound }.map { $0 + 1 } ?? 0
    return first..<max(first, end)
  }

  /// The display row of the bar of the run at `index`.
  func barRow(ofRun index: Int) -> Int {
    barRows[index]
  }

  /// Whether `row` lies in a run behind its first row, so that the pane lays out no text for it.
  ///
  /// The first row of a run holds the place of the bar.
  func isHidden(row: Int) -> Bool {
    guard let index = runIndex(containingRow: row) else { return false }
    return row != runs[index].rows.lowerBound
  }

  /// The display position of a row position of the grid, both counted in rows from the top.
  func displayPosition(ofRow position: Double) -> Double {
    guard rowCount > 0 else { return position }
    let row = min(max(Int(position.rounded(.down)), 0), rowCount - 1)
    let fraction = position - Double(row)
    guard let index = runIndex(containingRow: row) else {
      return Double(displayRow(ofRow: row)) + fraction
    }
    let run = runs[index].rows
    return Double(barRows[index]) + (Double(row - run.lowerBound) + fraction) / Double(run.count)
  }

  /// The row position of the grid at a display position, both counted in rows from the top.
  func rowPosition(ofDisplay position: Double) -> Double {
    guard count > 0 else { return position }
    let displayRow = min(max(Int(position.rounded(.down)), 0), count - 1)
    let fraction = position - Double(displayRow)
    guard let index = runIndex(atDisplayRow: displayRow) else {
      return Double(row(atDisplayRow: displayRow)) + fraction
    }
    let run = runs[index].rows
    return Double(run.lowerBound) + fraction * Double(run.count)
  }

  /// The number of screen lines of all display rows.
  var lineCount: Int { firstLine(ofDisplayRow: count) }

  /// The first screen line of `displayRow`; for the end of the rows, the number of lines.
  func firstLine(ofDisplayRow displayRow: Int) -> Int {
    let index = tallRows.partitioningIndex { $0.displayRow >= displayRow } - 1
    guard index >= 0 else { return displayRow }
    let tall = tallRows[index]
    return tall.firstLine + tall.lines + displayRow - tall.displayRow - 1
  }

  /// The number of screen lines that `displayRow` takes.
  func lineCount(ofDisplayRow displayRow: Int) -> Int {
    let index = tallRows.partitioningIndex { $0.displayRow >= displayRow }
    return index < tallRows.count && tallRows[index].displayRow == displayRow
      ? tallRows[index].lines : 1
  }

  /// The screen lines that `displayRows` take.
  func lines(ofDisplayRows displayRows: Range<Int>) -> Range<Int> {
    let first = firstLine(ofDisplayRow: displayRows.lowerBound)
    return first..<max(firstLine(ofDisplayRow: displayRows.upperBound), first)
  }

  /// The screen lines that show `rows`: their own, or the line of the bar of a run that hides
  /// them.
  func lines(ofRows rows: Range<Int>) -> Range<Int> {
    lines(ofDisplayRows: displayRows(ofRows: rows))
  }

  /// The display row that takes screen line `line`; beyond the last line, the display rows
  /// that would follow one line each.
  func displayRow(atLine line: Int) -> Int {
    let index = tallRows.partitioningIndex { $0.firstLine > line } - 1
    guard index >= 0 else { return line }
    let tall = tallRows[index]
    let end = tall.firstLine + tall.lines
    return line < end ? tall.displayRow : tall.displayRow + 1 + line - end
  }

  /// The display row at `line`, clamped to the display rows.
  func clampedDisplayRow(atLine line: Int) -> Int {
    min(max(displayRow(atLine: line), 0), count - 1)
  }

  /// The screen-line position of a display position, both counted from the top.
  func linePosition(ofDisplay position: Double) -> Double {
    guard !tallRows.isEmpty else { return position }
    let displayRow = Int(position.rounded(.down))
    let fraction = position - Double(displayRow)
    return Double(firstLine(ofDisplayRow: displayRow))
      + fraction * Double(lineCount(ofDisplayRow: displayRow))
  }

  /// The display position of a screen-line position, both counted from the top.
  func displayPosition(ofLine position: Double) -> Double {
    guard !tallRows.isEmpty else { return position }
    let line = Int(position.rounded(.down))
    let displayRow = self.displayRow(atLine: line)
    let lines = Double(lineCount(ofDisplayRow: displayRow))
    return Double(displayRow) + (position - Double(firstLine(ofDisplayRow: displayRow))) / lines
  }

  /// The screen-line position of a row position of the grid, both counted from the top.
  func linePosition(ofRow position: Double) -> Double {
    linePosition(ofDisplay: displayPosition(ofRow: position))
  }

  /// The row position of the grid at a screen-line position, both counted from the top.
  func rowPosition(ofLine position: Double) -> Double {
    rowPosition(ofDisplay: displayPosition(ofLine: position))
  }

  /// The last index of the bars for which `isAtOrBefore` holds, given that once it fails, it
  /// fails for every later one.
  private func lastIndex(where isAtOrBefore: (Int) -> Bool) -> Int? {
    var low = 0
    var high = runs.count
    while low < high {
      let middle = (low + high) / 2
      if isAtOrBefore(middle) { low = middle + 1 } else { high = middle }
    }
    return low > 0 ? low - 1 : nil
  }

  /// The last index of the runs for which `isAtOrBefore` holds, given that once it fails, it
  /// fails for every later one.
  private func lastRun(where isAtOrBefore: (CollapsedRun) -> Bool) -> Int? {
    lastIndex { isAtOrBefore(runs[$0]) }
  }
}
