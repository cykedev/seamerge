import Testing

@testable import PaneKit

/// Checks the screen lines of rows that wrap: where each display row starts, how a bar and the
/// rows behind it count, how positions map both ways, and how the rows that wrap follow an edit
/// and merge across panes.
@Suite struct WrappedRowsTests {
  private typealias Entry = WrappedRows.Entry

  @Test func wrappedRowsPushTheRowsBelowThemDownByTheirExtraLines() {
    let rows = DisplayRows(
      runs: [], rowCount: 10,
      wrappedRows: WrappedRows([Entry(row: 2, lines: 3), Entry(row: 5, lines: 2)]))

    #expect((0..<11).map(rows.firstLine(ofDisplayRow:)) == [0, 1, 2, 5, 6, 7, 9, 10, 11, 12, 13])
    #expect(rows.lineCount == 13)
    #expect((0..<10).map(rows.lineCount(ofDisplayRow:)) == [1, 1, 3, 1, 1, 2, 1, 1, 1, 1])
    #expect((0..<13).map(rows.displayRow(atLine:)) == [0, 1, 2, 2, 2, 3, 4, 5, 5, 6, 7, 8, 9])
    #expect(rows.lines(ofRows: 2..<3) == 2..<5)
    #expect(rows.lines(ofRows: 4..<4) == 6..<6)
  }

  @Test func aBarTakesOneLineAndTheRowsBehindItWrapNotAtAll() {
    let rows = DisplayRows(
      runs: [CollapsedRun(rows: 3..<8)], rowCount: 12,
      wrappedRows: WrappedRows([
        Entry(row: 1, lines: 2), Entry(row: 3, lines: 4), Entry(row: 6, lines: 3),
        Entry(row: 9, lines: 2),
      ]))

    #expect(rows.count == 8)
    #expect(rows.lineCount == 10)
    #expect(rows.lines(ofRows: 3..<8) == 4..<5)
    #expect(rows.lines(ofRows: 9..<10) == 6..<8)
  }

  @Test func positionsMapToLinesAndBackAtEveryFraction() {
    let rows = DisplayRows(
      runs: [CollapsedRun(rows: 10..<20)], rowCount: 40,
      wrappedRows: WrappedRows([
        Entry(row: 3, lines: 4), Entry(row: 15, lines: 3), Entry(row: 25, lines: 2),
      ]))
    for step in 0..<(40 * 8) {
      let position = Double(step) / 8
      let line = rows.linePosition(ofRow: position)
      #expect(abs(rows.rowPosition(ofLine: line) - position) < 1e-9, "position \(position)")
    }
    // Within a row of four lines, the second line starts a quarter down the row.
    #expect(rows.linePosition(ofRow: 3.25) == 4)
  }

  @Test func mergingTakesTheMostLinesOfEachRow() {
    let first = WrappedRows([Entry(row: 1, lines: 2), Entry(row: 4, lines: 5)])
    let second = WrappedRows([Entry(row: 1, lines: 3), Entry(row: 2, lines: 2)])

    #expect(
      first.merged(with: second)
        == WrappedRows([Entry(row: 1, lines: 3), Entry(row: 2, lines: 2), Entry(row: 4, lines: 5)]))
    #expect(first.merged(with: .none) == first)
    #expect(first.clamped(toRowCount: 4) == WrappedRows([Entry(row: 1, lines: 2)]))
  }

  @Test func anEditKeepsTheRowsBeforeItMovesThoseAfterItAndRewritesItsOwn() {
    var rows = WrappedRows([
      Entry(row: 1, lines: 2), Entry(row: 5, lines: 3), Entry(row: 9, lines: 2),
    ])
    // Rows 4 to 6 became two rows, of which the second wraps.
    rows.takeOver(
      RowChange(oldRows: 4..<7, newRows: 4..<6), rewritten: [Entry(row: 5, lines: 4)])

    #expect(
      rows
        == WrappedRows([
          Entry(row: 1, lines: 2), Entry(row: 5, lines: 4), Entry(row: 8, lines: 2),
        ]))
  }
}
