/// A run of rows that a pane hides behind a bar one row high.
///
/// The text of the rows stays in the pane: a selection across the bar copies it, and the find
/// bar finds it. Panes on the same grid collapse the same runs, so that their rows stay aligned.
public struct CollapsedRun: Sendable, Hashable {
  /// The rows that the run hides, on the pane's grid.
  public var rows: Range<Int>

  /// Creates a run.
  ///
  /// - Precondition: `rows` is not empty.
  public init(rows: Range<Int>) {
    precondition(!rows.isEmpty, "A collapsed run hides at least one row")
    self.rows = rows
  }
}
