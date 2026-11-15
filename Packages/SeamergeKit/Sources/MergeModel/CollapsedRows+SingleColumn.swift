extension CollapsedRows {
  /// The rows of `layout` that `run` hides, so that a single column collapses the same runs as
  /// the panes side by side.
  ///
  /// A run lies in an unchanged block, whose rows lie in the same order in the column and on the
  /// grid, so the run hides as many rows of the column as of the grid.
  ///
  /// - Precondition: `layout` lays out the session that the runs were found in.
  public func rows(of run: Run, in layout: SingleColumnLayout) -> Range<Int> {
    let offset = layout.rows(of: run.block).lowerBound - rowLayout.rows(of: run.block).lowerBound
    return run.rows.lowerBound + offset..<run.rows.upperBound + offset
  }

  /// Expands the run that hides `row` of `layout`, so that a target there, such as a match of a
  /// search or a jump, comes into view.
  ///
  /// - Returns: Whether a run was expanded.
  /// - Precondition: `layout` lays out the session that the runs were found in, and `row` lies
  ///   within `0..<layout.rowCount`.
  @discardableResult
  public mutating func expandToShow(row: Int, in layout: SingleColumnLayout) -> Bool {
    guard layout.place(atRow: row).block.kind == .unchanged else { return false }
    return expandToShow(row: layout.gridRow(ofUnchangedRow: row))
  }
}
