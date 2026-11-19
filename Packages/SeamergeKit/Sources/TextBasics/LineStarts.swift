/// Where the lines of a text start, counted in any unit: bytes, UTF-16 code units or rows.
///
/// The table holds the offset where each line starts, followed by the offset where the last line
/// ends, so that line *n* reaches from the start of line *n* to the start of line *n* + 1.
package struct LineStarts: Sendable, Hashable {
  @usableFromInline var offsets: [Int]

  /// Creates the table from the start of each line, followed by the end of the last line.
  ///
  /// - Precondition: `offsets` is not empty and does not decrease.
  @inlinable
  package init(_ offsets: [Int]) {
    precondition(!offsets.isEmpty, "Line starts end with the end of the text")
    self.offsets = offsets
  }

  /// The number of lines.
  @inlinable
  package var lineCount: Int { offsets.count - 1 }

  /// The offset where `line` starts, or for ``lineCount``, where the last line ends.
  ///
  /// - Precondition: `line` lies within `0...lineCount`.
  @inlinable
  package subscript(line: Int) -> Int { offsets[line] }

  /// The offsets of `line`, from its start to the start of the line after it.
  ///
  /// - Precondition: `line` lies within `0..<lineCount`.
  @inlinable
  package func range(ofLine line: Int) -> Range<Int> { offsets[line]..<offsets[line + 1] }

  /// The last line that starts at or before `offset`: the line that holds it, where the end of
  /// the text and anything after it belong to the last line, and anything before the text to the
  /// first; 0 if there is no line.
  @inlinable
  package func line(containing offset: Int) -> Int {
    (0..<lineCount).lastIndex(holding: { offsets[$0] <= offset })
  }

  /// Replaces `lines` by lines that start where the first of them does and at `starts`, and
  /// moves the lines after them, and the end of the text, by `distance`.
  ///
  /// The table follows an edit this way that rewrote `lines` into `starts.count + 1` lines and
  /// changed the length of the text by `distance`.
  ///
  /// - Precondition: `lines` is not empty and lies within `0..<lineCount`.
  package mutating func replaceLines(
    _ lines: Range<Int>, withLinesStartingAt starts: [Int], movingLaterLinesBy distance: Int
  ) {
    precondition(
      !lines.isEmpty && lines.upperBound <= lineCount, "Lines \(lines) are out of range")
    offsets.replaceSubrange(lines.lowerBound + 1..<lines.upperBound, with: starts)
    for index in lines.lowerBound + 1 + starts.count..<offsets.count {
      offsets[index] += distance
    }
  }
}
