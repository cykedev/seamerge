/// A run of rows that a pane hides behind a bar one row high.
///
/// The text of the rows stays in the pane: a selection across the bar copies it, and the find
/// bar finds it. Panes on the same grid collapse the same runs, so that their rows stay aligned.
///
/// A run may also stand for lines that the pane does not have, such as the lines that a patch
/// passes over between two of its hunks: its bar names them, and it never expands.
package struct CollapsedRun: Sendable, Hashable {
  /// The rows that the run hides, on the pane's grid.
  package var rows: Range<Int>

  /// The number of lines that the run stands for although the pane does not have them, or `nil`
  /// for a run of rows the pane holds, which expands.
  package var missingLineCount: Int?

  /// Creates a run.
  ///
  /// - Precondition: `rows` is not empty.
  package init(rows: Range<Int>, missingLineCount: Int? = nil) {
    precondition(!rows.isEmpty, "A collapsed run hides at least one row")
    self.rows = rows
    self.missingLineCount = missingLineCount
  }

  /// Whether the run can be expanded: it hides rows of the pane rather than standing for lines
  /// the pane does not have.
  package var expands: Bool {
    missingLineCount == nil
  }
}
