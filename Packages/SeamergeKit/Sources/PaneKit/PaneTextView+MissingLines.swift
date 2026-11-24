import AppKit

extension PaneTextView {
  /// Whether `row` stands for no line of the file: a filler row, or the row of a collapsed run
  /// that stands for lines the pane does not have, as the placeholder of a gap in a patch.
  ///
  /// Copying and searching leave such rows out, and VoiceOver hears no text in them.
  func standsForNoLine(row: Int) -> Bool {
    if content.isFiller(row: row) { return true }
    guard let index = displayRows.runIndex(containingRow: row) else { return false }
    return !displayRows.runs[index].expands
  }

  /// The text of the rows of runs that stand for lines the pane does not have, without their
  /// line feeds, in order.
  private var missingLineRanges: [Range<Int>] {
    displayRows.runs.filter { !$0.expands }.flatMap { run in
      run.rows.compactMap { row -> Range<Int>? in
        guard row < grid.rowCount else { return nil }
        let line = grid.offsets(ofRow: row)
        let endsWithLineFeed =
          !line.isEmpty && (string as NSString).character(at: line.upperBound - 1) == 0x0A
        return line.lowerBound..<line.upperBound - (endsWithLineFeed ? 1 : 0)
      }
    }
  }

  /// The parts of `span` of the text that lie in rows that stand for lines the pane does not
  /// have, relative to the start of `span`.
  private func missingParts(of span: Range<Int>) -> [NSRange] {
    missingLineRanges.filter { $0.overlaps(span) }.map { range in
      let part = range.clamped(to: span)
      return NSRange(location: part.lowerBound - span.lowerBound, length: part.count)
    }
  }

  /// The text for VoiceOver, with the characters of rows that stand for lines the pane does not
  /// have turned into spaces, so that every offset stays where it is; their bars name those
  /// lines.
  override func accessibilityValue() -> String? {
    // Most panes have no such rows; they answer without a copy of the whole text.
    guard displayRows.runs.contains(where: { !$0.expands }) else {
      return super.accessibilityValue()
    }
    let masked = NSMutableString(string: string)
    for part in missingParts(of: 0..<masked.length) {
      masked.replaceCharacters(in: part, with: String(repeating: " ", count: part.length))
    }
    return masked as String
  }
}
