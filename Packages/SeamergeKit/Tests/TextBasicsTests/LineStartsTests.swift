import Testing
import TextBasics

struct LineStartsTests {
  @Test func describesEachLineFromItsStartToTheNext() {
    let starts = LineStarts([0, 4, 4, 9])

    #expect(starts.lineCount == 3)
    #expect(starts.range(ofLine: 0) == 0..<4)
    #expect(starts.range(ofLine: 1) == 4..<4)
    #expect(starts.range(ofLine: 2) == 4..<9)
    #expect(starts[3] == 9)
  }

  @Test func offsetBelongsToTheLastLineStartingAtOrBeforeIt() {
    let starts = LineStarts([0, 4, 4, 9])

    #expect(starts.line(containing: 0) == 0)
    #expect(starts.line(containing: 3) == 0)
    #expect(starts.line(containing: 4) == 2)
    #expect(starts.line(containing: 8) == 2)
  }

  @Test func endOfTheTextBelongsToTheLastLine() {
    let starts = LineStarts([0, 4, 9])

    #expect(starts.line(containing: 9) == 1)
    #expect(starts.line(containing: 20) == 1)
  }

  @Test func offsetBeforeTheTextBelongsToTheFirstLine() {
    #expect(LineStarts([3, 5, 8]).line(containing: 1) == 0)
  }

  @Test func textWithoutLinesAnswersLineZero() {
    let starts = LineStarts([0])

    #expect(starts.lineCount == 0)
    #expect(starts.line(containing: 0) == 0)
  }

  @Test func lineContainingAgreesWithALinearSearchForEverySmallTable() {
    for table in Self.nonDecreasingTables(maximumCount: 5, maximumOffset: 4) {
      let starts = LineStarts(table)
      for offset in -1...5 {
        let expected = (0..<max(starts.lineCount, 1)).last { $0 == 0 || table[$0] <= offset } ?? 0
        #expect(starts.line(containing: offset) == expected, "\(table), offset \(offset)")
      }
    }
  }

  /// Every non-decreasing table of one to `maximumCount` offsets within `0...maximumOffset`.
  private static func nonDecreasingTables(maximumCount: Int, maximumOffset: Int) -> [[Int]] {
    var tables: [[Int]] = (0...maximumOffset).map { [$0] }
    var longer = tables
    for _ in 1..<maximumCount {
      longer = longer.flatMap { table in
        (table[table.count - 1]...maximumOffset).map { table + [$0] }
      }
      tables += longer
    }
    return tables
  }
}
