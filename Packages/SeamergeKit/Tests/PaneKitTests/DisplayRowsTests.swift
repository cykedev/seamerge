import Testing

@testable import PaneKit

/// Checks the one place that maps the rows of a pane's grid to the rows it shows, with runs at the
/// edges, side by side and at random, both ways and at fractional positions.
@Suite struct DisplayRowsTests {
  @Test func rowsBeforeBetweenAndAfterRunsMapOneToOne() {
    let rows = DisplayRows(
      runs: [CollapsedRun(rows: 3..<10), CollapsedRun(rows: 12..<20)], rowCount: 25)

    #expect(rows.count == 25 - 6 - 7)
    #expect((0..<3).map(rows.displayRow(ofRow:)) == [0, 1, 2])
    #expect((3..<10).allSatisfy { rows.displayRow(ofRow: $0) == 3 })
    #expect(rows.displayRow(ofRow: 10) == 4)
    #expect((12..<20).allSatisfy { rows.displayRow(ofRow: $0) == 6 })
    #expect(rows.displayRow(ofRow: 24) == 11)
    #expect(
      (0..<rows.count).map(rows.row(atDisplayRow:)) == [0, 1, 2, 3, 10, 11, 12, 20, 21, 22, 23, 24])
    #expect(rows.runIndex(atDisplayRow: 3) == 0)
    #expect(rows.runIndex(atDisplayRow: 6) == 1)
    #expect(rows.runIndex(atDisplayRow: 4) == nil)
  }

  @Test func runsAtTheEdgesAndRunsSideBySideMapToTheirBars() {
    let edges = DisplayRows(
      runs: [CollapsedRun(rows: 0..<5), CollapsedRun(rows: 5..<9), CollapsedRun(rows: 12..<15)],
      rowCount: 15)

    #expect(edges.count == 6)
    #expect(edges.displayRows(ofRows: 0..<15) == 0..<6)
    #expect((0..<edges.count).map(edges.row(atDisplayRow:)) == [0, 5, 9, 10, 11, 12])
    #expect(edges.barRow(ofRun: 2) == 5)
    #expect(edges.runIndices(withBarsIn: 1..<6) == 1..<3)

    let whole = DisplayRows(runs: [CollapsedRun(rows: 0..<12)], rowCount: 12)
    #expect(whole.count == 1)
    #expect(whole.displayRow(ofRow: 11) == 0)
    #expect(!whole.isHidden(row: 0))
    #expect(whole.isHidden(row: 11))
  }

  @Test func positionWithinABarSpansItsRowsEvenly() {
    let rows = DisplayRows(runs: [CollapsedRun(rows: 10..<110)], rowCount: 200)

    #expect(rows.displayPosition(ofRow: 60) == 10.5)
    #expect(rows.rowPosition(ofDisplay: 10.5) == 60)
    #expect(rows.displayPosition(ofRow: 115.75) == 16.75)
    #expect(rows.rowPosition(ofDisplay: 16.75) == 115.75)
  }

  /// Random grids with random runs, from the fixed seed 2026.
  @Test func randomRunsMapRowsAndDisplayRowsBothWays() {
    var generator = SplitMix64(seed: 2026)
    for _ in 0..<500 {
      let rowCount = Int.random(in: 1...300, using: &generator)
      var runs: [CollapsedRun] = []
      var row = 0
      while row < rowCount {
        row += Int.random(in: 0...12, using: &generator)
        let length = Int.random(in: 1...30, using: &generator)
        guard row + length <= rowCount, Bool.random(using: &generator) else { continue }
        runs.append(CollapsedRun(rows: row..<row + length))
        row += length
      }
      let rows = DisplayRows(runs: runs, rowCount: rowCount)
      var shown = 0
      for displayRow in 0..<rows.count {
        let row = rows.row(atDisplayRow: displayRow)
        #expect(rows.displayRow(ofRow: row) == displayRow)
        if let index = rows.runIndex(atDisplayRow: displayRow) {
          #expect(row == runs[index].rows.lowerBound)
          #expect(rows.barRow(ofRun: index) == displayRow)
          shown += runs[index].rows.count
        } else {
          #expect(rows.runIndex(containingRow: row) == nil)
          shown += 1
        }
      }
      #expect(shown == rowCount)
      for row in 0..<rowCount {
        let index = rows.runIndex(containingRow: row)
        #expect(index == runs.firstIndex { $0.rows.contains(row) })
        #expect(rows.isHidden(row: row) == (index.map { row != runs[$0].rows.lowerBound } ?? false))
        let position = Double(row) + 0.25
        let back = rows.rowPosition(ofDisplay: rows.displayPosition(ofRow: position))
        #expect(abs(back - position) < 1e-9)
      }
    }
  }
}
