public import Foundation

extension InlineHighlights {
  /// The highlights of the lines of `role` in a single column, as UTF-16 ranges in its
  /// ``SingleColumnLayout/displayText``: the same changed characters and removal marks as on
  /// the pane of `role`, on the rows that show its lines.
  ///
  /// Only changed blocks have highlights, and their rows show the lines of one side, so the
  /// highlights of both sides lie on rows of their own; together they are the highlights between
  /// the two parts of a block. The ranges are sorted and do not overlap.
  ///
  /// - Precondition: The highlights belong to a block of the session that `layout` lays out, and
  ///   `role` is one of its sides.
  public func ranges(in role: Role, on layout: SingleColumnLayout) -> [Range<Int>] {
    let ranges = ranges(in: role)
    guard !ranges.isEmpty, let gridText = layout.rowLayout.displayText(for: role) else {
      return []
    }
    return ranges.map { range in
      let gridRow = gridText.row(containingOffset: range.lowerBound)
      guard let line = layout.rowLayout.line(atRow: gridRow, in: role) else {
        preconditionFailure("A highlight lies on a filler row")
      }
      let start =
        layout.displayText.utf16Range(ofRow: layout.row(ofLine: line, in: role)).lowerBound
        + range.lowerBound - gridText.utf16Range(ofRow: gridRow).lowerBound
      return start..<start + range.count
    }
  }
}

extension IgnoredDifferences {
  /// The rows of `layout` whose lines differ, although the comparison counts them as equal: a
  /// row that the sides share where either line differs from the other, and a row of one side
  /// whose line is among the differing lines.
  ///
  /// A shared row shows the text of the second side, so its mark is what tells that the line of
  /// the first side is not the same.
  ///
  /// - Precondition: The differences were found in the session that `layout` lays out.
  public func rows(on layout: SingleColumnLayout) -> IndexSet {
    var rows = IndexSet()
    for role in [Role.a, .b] {
      for line in lines(in: role) {
        rows.insert(layout.row(ofLine: line, in: role))
      }
    }
    return rows
  }

  /// The places where the lines of `layout` differ, as UTF-16 ranges in its
  /// ``SingleColumnLayout/displayText``, sorted and apart.
  ///
  /// A row of one side has the places of its line. A row that the sides share shows the text of
  /// the second side and has the places of that line: the characters it has in place of those
  /// of the first side. A line of the second side that only lacks text of the first has none, and
  /// its row keeps only its mark among ``rows(on:)``.
  ///
  /// - Precondition: `session` is the session the differences were found in and that `layout`
  ///   lays out.
  /// - Throws: The error of the comparison.
  public func places(
    on layout: SingleColumnLayout, of session: Session
  ) throws(MergeModelError) -> [Range<Int>] {
    let secondSide: Role = layout.firstSide == .a ? .b : .a
    var ranges: [Range<Int>] = []
    for role in [layout.firstSide, secondSide] {
      for place in try places(in: role, of: session) {
        let row = layout.row(ofLine: place.line, in: role)
        // A shared row shows the line of the second side only.
        guard role == secondSide || layout.place(atRow: row).side != nil else { continue }
        let start = layout.displayText.utf16Range(ofRow: row).lowerBound
        ranges.append(start + place.range.lowerBound..<start + place.range.upperBound)
      }
    }
    return ranges.sorted { $0.lowerBound < $1.lowerBound }
  }
}
