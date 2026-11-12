/// The rows of a pane as it shows them: every row of its grid, except that each collapsed run
/// takes a single *display row*, the row of its bar.
///
/// Display row *d* lies at `d × rowHeight` from the top of the text. Positions may be fractional,
/// so that coupled panes can match a place within a bar too: the bar spans its hidden rows
/// evenly.
struct DisplayRows {
  /// The collapsed runs, in row order.
  let runs: [CollapsedRun]

  /// The number of rows of the grid.
  let rowCount: Int

  /// The display row of the bar of each run, followed by the number of display rows.
  private let barRows: [Int]

  /// Collapses `runs` of a grid with `rowCount` rows.
  ///
  /// - Precondition: The runs are sorted, do not overlap and lie within the rows.
  init(runs: [CollapsedRun], rowCount: Int) {
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
  }

  /// The number of display rows.
  var count: Int { barRows[barRows.count - 1] }

  /// The display row that shows `row`: its own, or the bar of the run that hides it.
  func displayRow(ofRow row: Int) -> Int {
    guard let index = lastRun(where: { $0.rows.lowerBound <= row }) else { return row }
    let run = runs[index]
    return run.rows.contains(row) ? barRows[index] : barRows[index] + 1 + row - run.rows.upperBound
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
