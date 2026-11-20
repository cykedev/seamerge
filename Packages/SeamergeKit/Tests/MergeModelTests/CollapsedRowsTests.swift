import MergeModel
import Testing

struct CollapsedRowsTests {
  /// `count` lines named `name0`, `name1` and so on, each with a line feed.
  static func lines(_ name: String, _ count: Int) -> String {
    (0..<count).map { "\(name)\($0)\n" }.joined()
  }

  /// A comparison with a change on the first and on the last line and `count` unchanged lines
  /// between them.
  static func comparison(unchangedBetween count: Int) async throws -> Session {
    try await diff("old\n" + lines("u", count) + "old end\n", "new\n" + lines("u", count) + "new\n")
  }

  @Test func unchangedBlockOfEightRowsCollapsesBetweenThreeRowsOfContext() async throws {
    let session = try await Self.comparison(unchangedBetween: 8)
    let collapsed = CollapsedRows(session: session)

    #expect(collapsed.runs.map(\.rows) == [4..<6])
    #expect(collapsed.runs.first?.block.kind == .unchanged)
    #expect(collapsed.run(containingRow: 3) == nil)
    #expect(collapsed.run(containingRow: 4) == collapsed.runs.first)
    #expect(collapsed.run(containingRow: 5) == collapsed.runs.first)
    #expect(collapsed.run(containingRow: 6) == nil)
  }

  @Test func runHidesTheSameLinesOfEachSideBeyondInsertionsAndRemovals() async throws {
    let session = try await diff(
      "gone1\ngone2\ngone3\n" + Self.lines("u", 12) + "old\n" + Self.lines("v", 10),
      Self.lines("u", 12) + "new\nnew2\n" + Self.lines("v", 10))
    let collapsed = CollapsedRows(session: session)
    try #require(collapsed.runs.count == 2)
    let (first, last) = (collapsed.runs[0], collapsed.runs[1])

    // The grid has three rows of the removal before the first run.
    #expect(first.rows == 6..<12)
    #expect(collapsed.lines(of: first, in: .a) == 6..<12)
    #expect(collapsed.lines(of: first, in: .b) == 3..<9)
    // The last run reaches the end of both files.
    #expect(last.rows == 20..<27)
    #expect(collapsed.lines(of: last, in: .a) == 19..<26)
    #expect(collapsed.lines(of: last, in: .b) == 17..<24)
    let map = ScrollMap(session: session, from: .lines(.a), to: .lines(.b))
    for run in collapsed.runs {
      let lines = collapsed.lines(of: run, in: .a)
      let mapped = map.targetPosition(at: Double(lines.lowerBound))
      #expect(Int(mapped) == collapsed.lines(of: run, in: .b).lowerBound)
    }
  }

  @Test func unchangedBlockOfSevenRowsStaysExpanded() async throws {
    let collapsed = try await CollapsedRows(session: Self.comparison(unchangedBetween: 7))

    #expect(collapsed.runs.isEmpty)
  }

  @Test func runsAtTheStartAndTheEndOfTheFilesKeepNoContextTowardsTheEdge() async throws {
    let session = try await diff(
      Self.lines("u", 10) + "old\n" + Self.lines("v", 10),
      Self.lines("u", 10) + "new\n"
        + Self.lines("v", 10))
    let collapsed = CollapsedRows(session: session)

    #expect(collapsed.runs.map(\.rows) == [0..<7, 14..<21])
    try expectRunsFollowTheRule(collapsed, of: session)
  }

  @Test func filesWithoutAnyChangeCollapseIntoOneRow() async throws {
    let collapsed = try await CollapsedRows(
      session: diff(Self.lines("u", 12), Self.lines("u", 12)))

    #expect(collapsed.runs.map(\.rows) == [0..<12])
  }

  @Test func everyLongUnchangedBlockOfAComparisonCollapses() async throws {
    let session = try await diff(
      Self.lines("u", 9) + "a\n" + Self.lines("v", 20) + "b\nc\n" + Self.lines("w", 8),
      Self.lines("u", 9) + Self.lines("v", 20) + "B\n" + Self.lines("w", 8) + "added\n")
    let collapsed = CollapsedRows(session: session)

    #expect(collapsed.runs.map(\.rows) == [0..<6, 13..<27, 35..<37])
    try expectRunsFollowTheRule(collapsed, of: session)
  }

  @Test func linesThatASideAndBShareCollapseInAMergeWithoutABase() async throws {
    let session = try await merge(
      base: nil, a: Self.lines("u", 10) + "a\n" + Self.lines("v", 12),
      b: Self.lines("u", 10) + "b\n" + Self.lines("v", 12))
    let collapsed = CollapsedRows(session: session)

    #expect(collapsed.runs.map(\.rows) == [0..<7, 14..<23])
    #expect(collapsed.runs.allSatisfy { $0.block.kind == .changedInBoth })
    try expectRunsFollowTheRule(collapsed, of: session)
  }

  @Test func changedBlockWithFillerRowsStaysExpandedBetweenRuns() async throws {
    let session = try await merge(
      base: Self.lines("u", 9) + "x\n" + Self.lines("v", 9),
      a: Self.lines("u", 9) + "a\nand more\nand more\n" + Self.lines("v", 9),
      b: Self.lines("u", 9) + Self.lines("v", 9))
    let collapsed = CollapsedRows(session: session)

    #expect(collapsed.runs.map(\.rows) == [0..<6, 15..<21])
    #expect((6..<15).allSatisfy { collapsed.run(containingRow: $0) == nil })
    try expectRunsFollowTheRule(collapsed, of: session)
  }

  @Test func expandedRunShowsItsRowsAndTheOthersStayCollapsed() async throws {
    let session = try await diff(
      Self.lines("u", 10) + "old\n" + Self.lines("v", 10),
      Self.lines("u", 10) + "new\n"
        + Self.lines("v", 10))
    var collapsed = CollapsedRows(session: session)

    collapsed.expand(collapsed.runs[0])

    #expect(collapsed.runs.map(\.rows) == [14..<21])
    #expect(collapsed.run(containingRow: 3) == nil)
  }

  @Test func targetInACollapsedRunExpandsIt() async throws {
    let session = try await Self.comparison(unchangedBetween: 20)
    var collapsed = CollapsedRows(session: session)

    let expandedForContext = collapsed.expandToShow(row: 2)
    let expandedForLine = collapsed.expandToShow(line: 10, in: .b)

    #expect(!expandedForContext)
    #expect(expandedForLine)
    #expect(collapsed.runs.isEmpty)
    let expandedAgain = collapsed.expandToShow(line: 10, in: .b)
    #expect(!expandedAgain)
  }

  @Test func showingAllRowsAndCollapsingAgainForgetsWhatWasExpanded() async throws {
    let session = try await Self.comparison(unchangedBetween: 20)
    var collapsed = CollapsedRows(session: session)
    collapsed.expandToShow(row: 10)

    collapsed.showAllRows()
    #expect(!collapsed.collapsesUnchangedRows)
    #expect(collapsed.runs.isEmpty)

    collapsed.collapseUnchangedRows(document: nil, caretRow: nil)
    #expect(collapsed.runs.map(\.rows) == [4..<18])
  }

  @Test func panesThatShowAllRowsHaveNoRuns() async throws {
    let session = try await Self.comparison(unchangedBetween: 20)
    let collapsed = CollapsedRows(session: session, collapsesUnchangedRows: false)

    #expect(collapsed.runs.isEmpty)
    #expect(collapsed.run(containingRow: 10) == nil)
  }

  @Test func runWithTheInsertionPointNeverCollapses() async throws {
    let session = try await Self.comparison(unchangedBetween: 20)

    let collapsed = CollapsedRows(session: session, caretRow: 10)
    #expect(collapsed.runs.isEmpty)

    var shown = CollapsedRows(session: session, collapsesUnchangedRows: false)
    shown.collapseUnchangedRows(document: nil, caretRow: 4)
    #expect(shown.runs.isEmpty)
    shown.collapseUnchangedRows(document: nil, caretRow: 3)
    #expect(shown.runs.map(\.rows) == [4..<18])
  }

  @Test func runWhoseResultIsEditedNeverCollapses() async throws {
    let session = try await merge(
      base: "x\n" + Self.lines("u", 20) + "y\n", a: "a\n" + Self.lines("u", 20) + "y\n",
      b: "x\n" + Self.lines("u", 20) + "b\n")
    var buffer = ResultBuffer(session)
    let unchanged = try #require(session.blocks.first { $0.kind == .unchanged })
    var collapsed = CollapsedRows(session: session, document: buffer.document)
    #expect(collapsed.runs.map(\.block) == [unchanged])

    buffer.type("typed ", at: buffer.document.range(of: unchanged).lowerBound + 30)
    collapsed.keepWorkExpanded(in: buffer.document)
    #expect(collapsed.runs.isEmpty)

    buffer.undo()
    collapsed.keepWorkExpanded(in: buffer.document)
    #expect(collapsed.runs.isEmpty)
    collapsed.collapseUnchangedRows(document: buffer.document, caretRow: nil)
    #expect(collapsed.runs.map(\.block) == [unchanged])

    buffer.type("typed ", at: buffer.document.range(of: unchanged).lowerBound + 30)
    collapsed.collapseUnchangedRows(document: buffer.document, caretRow: nil)
    #expect(collapsed.runs.isEmpty)
    #expect(CollapsedRows(session: session, document: buffer.document).runs.isEmpty)
  }

  @Test func runWhoseResultIsChosenNeverCollapses() async throws {
    let session = try await merge(
      base: "x\n" + Self.lines("u", 20), a: "a\n" + Self.lines("u", 20),
      b: "x\n" + Self.lines("u", 20))
    var buffer = ResultBuffer(session)
    let unchanged = try #require(session.blocks.first { $0.kind == .unchanged })
    var collapsed = CollapsedRows(session: session, document: buffer.document)
    #expect(collapsed.runs.map(\.rows) == [4..<21])

    buffer.perform(buffer.document.planChoosing([], in: unchanged))
    collapsed.keepWorkExpanded(in: buffer.document)

    #expect(buffer.document.segment(for: unchanged).state == .chosen)
    #expect(collapsed.runs.isEmpty)
  }

  @Test func expandedRunCollapsesAgainOnItsOwn() async throws {
    let session = try await diff(
      Self.lines("u", 10) + "old\n" + Self.lines("v", 10) + "old\n" + Self.lines("w", 10),
      Self.lines("u", 10) + "new\n" + Self.lines("v", 10) + "new\n" + Self.lines("w", 10))
    var collapsed = CollapsedRows(session: session)
    try #require(collapsed.runs.count == 3)
    #expect(collapsed.expandedRuns.isEmpty)
    let first = collapsed.runs[0]
    let second = collapsed.runs[1]
    collapsed.expand(first)
    collapsed.expand(second)
    #expect(collapsed.expandedRuns == [first, second])

    let didCollapse = collapsed.collapse(second)
    #expect(didCollapse)
    #expect(collapsed.runs.contains(second) && !collapsed.runs.contains(first))
    #expect(collapsed.expandedRuns == [first])
    // A run that is collapsed already, or every run while all rows show, does not change.
    let didCollapseAgain = collapsed.collapse(second)
    #expect(!didCollapseAgain)
    collapsed.showAllRows()
    #expect(collapsed.expandedRuns.isEmpty)
    let didCollapseWhileAllShow = collapsed.collapse(first)
    #expect(!didCollapseWhileAllShow)
    #expect(collapsed.runs.isEmpty)
  }

  @Test func runWithWorkInTheResultNeverCollapsesOnItsOwn() async throws {
    let session = try await merge(
      base: "x\n" + Self.lines("u", 20) + "y\n", a: "a\n" + Self.lines("u", 20) + "y\n",
      b: "x\n" + Self.lines("u", 20) + "b\n")
    var buffer = ResultBuffer(session)
    let unchanged = try #require(session.blocks.first { $0.kind == .unchanged })
    var collapsed = CollapsedRows(session: session, document: buffer.document)
    let run = try #require(collapsed.runs.first)

    buffer.type("typed ", at: buffer.document.range(of: unchanged).lowerBound + 30)
    collapsed.keepWorkExpanded(in: buffer.document)
    buffer.undo()
    collapsed.keepWorkExpanded(in: buffer.document)

    #expect(collapsed.expandedRuns.isEmpty)
    let didCollapseOverWork = collapsed.collapse(run)
    #expect(!didCollapseOverWork)
    #expect(collapsed.runs.isEmpty)
    // Collapse Unchanged Lines forgets the work that was undone; the run collapses then.
    collapsed.collapseUnchangedRows(document: buffer.document, caretRow: nil)
    #expect(collapsed.runs == [run])
    collapsed.expand(run)
    #expect(collapsed.expandedRuns == [run])
  }

  @Test func resultHidesTheLinesOfTheRunOneForOne() async throws {
    let session = try await merge(
      base: "x\n" + Self.lines("u", 20) + "y\n",
      a: "a\nmore of a\n" + Self.lines("u", 20) + "y\n",
      b: "x\n" + Self.lines("u", 20) + "b\n")
    let buffer = ResultBuffer(session)
    let collapsed = CollapsedRows(session: session, document: buffer.document)
    let run = try #require(collapsed.runs.first)
    let map = ScrollMap(document: buffer.document, text: buffer.text)

    let lines = collapsed.resultLines(of: run, in: map)

    #expect(run.rows == 5..<19)
    #expect(lines == 5..<19)
    let resultLines = buffer.text.split(separator: "\n", omittingEmptySubsequences: false)
    #expect(resultLines[lines.lowerBound] == "u3")
    #expect(resultLines[lines.upperBound - 1] == "u16")
  }

  @Test func resultHidesTheRightLinesAfterABlockThatTookFewerLines() async throws {
    let session = try await merge(
      base: "x\ny\nz\n" + Self.lines("u", 20), a: "a\n" + Self.lines("u", 20),
      b: "x\ny\nz\n" + Self.lines("u", 20))
    let buffer = ResultBuffer(session)
    let collapsed = CollapsedRows(session: session, document: buffer.document)
    let run = try #require(collapsed.runs.first)

    let lines = collapsed.resultLines(
      of: run, in: ScrollMap(document: buffer.document, text: buffer.text))

    #expect(run.rows == 6..<23)
    #expect(lines == 4..<21)
    let resultLines = buffer.text.split(separator: "\n", omittingEmptySubsequences: false)
    #expect(resultLines[lines.lowerBound] == "u3")
    #expect(resultLines[lines.upperBound - 1] == "u19")
  }

  /// Random comparisons and merges, with and without a base, from the fixed seed 2026.
  @Test func runsOfRandomGridsFollowTheRule() async throws {
    var generator = SplitMix64(seed: 2026)
    for round in 0..<200 {
      var base = ""
      var a = ""
      var b = ""
      for chunk in 0..<Int.random(in: 1...6, using: &generator) {
        let shared = Self.lines("u\(chunk)_", Int.random(in: 0...20, using: &generator))
        base += shared
        a += shared
        b += shared
        base += Self.lines("x\(chunk)_", Int.random(in: 0...2, using: &generator))
        a += Self.lines("a\(chunk)_", Int.random(in: 0...3, using: &generator))
        b += Self.lines("b\(chunk)_", Int.random(in: 0...3, using: &generator))
      }
      let session =
        switch round % 3 {
        case 0: try await diff(a, b)
        case 1: try await merge(base: base, a: a, b: b)
        default: try await merge(base: nil, a: a, b: b)
        }
      var collapsed = CollapsedRows(session: session)
      for run in collapsed.runs where Bool.random(using: &generator) {
        collapsed.expand(run)
      }
      try expectRunsFollowTheRule(collapsed, of: session)
    }
  }

  /// Checks the runs against the rule: each long unchanged block collapses unless it is
  /// expanded, less the rows of context towards each neighbor, and every row knows its run.
  private func expectRunsFollowTheRule(
    _ collapsed: CollapsedRows, of session: Session,
    sourceLocation: SourceLocation = #_sourceLocation
  ) throws {
    let grid = session.rowLayout
    let hasBase = session.kind == .diff || session.inputs.base != nil
    let equalKinds: Set<Block.Kind> = hasBase ? [.unchanged] : [.unchanged, .changedInBoth]
    for run in collapsed.runs {
      let rows = grid.rows(of: run.block)
      #expect(equalKinds.contains(run.block.kind), sourceLocation: sourceLocation)
      #expect(rows.count >= CollapsedRows.minimumRowCount, sourceLocation: sourceLocation)
      let before = rows.lowerBound == 0 ? 0 : CollapsedRows.contextRowCount
      let after = rows.upperBound == grid.rowCount ? 0 : CollapsedRows.contextRowCount
      #expect(
        run.rows == rows.lowerBound + before..<rows.upperBound - after,
        sourceLocation: sourceLocation)
    }
    #expect(
      zip(collapsed.runs, collapsed.runs.dropFirst()).allSatisfy {
        $0.rows.upperBound <= $1.rows.lowerBound
      }, sourceLocation: sourceLocation)
    for row in 0..<grid.rowCount {
      #expect(
        collapsed.run(containingRow: row) == collapsed.runs.first { $0.rows.contains(row) },
        sourceLocation: sourceLocation)
    }
  }
}
