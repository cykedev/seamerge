/// The grid that the overview bar of a pane measures in while the pane's rows are not those of
/// the grid, such as the lines of a file without filler rows: the bar keeps its marks where they
/// stand on the grid and shows the visible part of the pane converted to it.
package struct OverviewGrid {
  /// The number of rows of the grid.
  package var rowCount: Int

  /// The runs that the panes on the grid hide behind bars, in rows of the grid.
  package var collapsedRuns: [CollapsedRun]

  /// The row of the grid, with its fraction, at a row of the pane with its fraction.
  package var gridRow: @MainActor (Double) -> Double

  /// The row of the pane, with its fraction, at a row of the grid with its fraction.
  package var paneRow: @MainActor (Double) -> Double

  /// Creates the grid of `rowCount` rows with `collapsedRuns`, whose rows `gridRow` and
  /// `paneRow` relate to the rows of the pane.
  ///
  /// - Precondition: The runs are sorted, do not overlap and lie within the rows.
  package init(
    rowCount: Int, collapsedRuns: [CollapsedRun],
    gridRow: @escaping @MainActor (Double) -> Double,
    paneRow: @escaping @MainActor (Double) -> Double
  ) {
    self.rowCount = rowCount
    self.collapsedRuns = collapsedRuns
    self.gridRow = gridRow
    self.paneRow = paneRow
  }

  /// The rows of the grid as the bar measures them, with the collapsed runs.
  var displayRows: DisplayRows {
    DisplayRows(runs: collapsedRuns, rowCount: max(rowCount, 1))
  }
}
