import Foundation
import MergeModel
import Testing

struct SingleColumnLayoutTests {
  @Test func insertedLinesShowOnceBetweenTheSharedOnes() async throws {
    let session = try await diff("a\nb\n", "a\nnew\nb\n")
    let layout = SingleColumnLayout(session: session)

    #expect(layout.rowDescriptions == ["1 1 a", "- 2 new", "2 3 b"])
    try expectRowsAndLinesAgree(in: layout, of: session)
  }

  @Test func removedLinesShowWithTheirOldNumberAlone() async throws {
    let session = try await diff("a\ngone\nb\n", "a\nb\n")
    let layout = SingleColumnLayout(session: session)

    #expect(layout.rowDescriptions == ["1 1 a", "2 - gone", "3 2 b"])
    try expectRowsAndLinesAgree(in: layout, of: session)
  }

  @Test func changedBlockShowsTheLinesOfTheLeftFileAboveThoseOfTheRight() async throws {
    let session = try await diff("a\nold 1\nold 2\nb\n", "a\nnew\nb\n")
    let layout = SingleColumnLayout(session: session)
    let changed = try #require(session.blocks.first { $0.kind == .changed })

    #expect(layout.rowDescriptions == ["1 1 a", "2 - old 1", "3 - old 2", "- 2 new", "4 3 b"])
    #expect(layout.rows(of: changed) == 1..<4)
    #expect(layout.rows(of: changed, showingOnly: .a) == 1..<3)
    #expect(layout.rows(of: changed, showingOnly: .b) == 3..<4)
    try expectRowsAndLinesAgree(in: layout, of: session)
  }

  @Test func swappedSidesShowTheLinesOfTheRightFileFirst() async throws {
    let session = try await diff("a\nold 1\nold 2\nb\n", "a\nnew\nb\n")
    let layout = SingleColumnLayout(session: session, firstSide: .b)
    let changed = try #require(session.blocks.first { $0.kind == .changed })

    #expect(layout.firstSide == .b)
    #expect(layout.rowDescriptions == ["1 1 a", "- 2 new", "2 - old 1", "3 - old 2", "4 3 b"])
    #expect(layout.rows(of: changed, showingOnly: .b) == 1..<2)
    #expect(layout.rows(of: changed, showingOnly: .a) == 2..<4)
    try expectRowsAndLinesAgree(in: layout, of: session)
  }

  @Test func movedLinesShowAtTheirOldPlaceAndAtTheirNewOne() async throws {
    let first = "func first() {\n  let value = compute(1)\n  return value\n}\n"
    let second = "func second() {\n  let other = compute(2)\n  return other\n}\n"
    let session = try await diff(first + second, second + first)
    let layout = SingleColumnLayout(session: session)
    let move = try #require(session.moves.first)

    let source = layout.rows(of: session.blocks[move.source.block], showingOnly: move.source.role)
    let destination = layout.rows(
      of: session.blocks[move.destination.block], showingOnly: move.destination.role)
    #expect(source.count == 4 && destination.count == 4)
    #expect(
      source.upperBound <= destination.lowerBound || destination.upperBound <= source.lowerBound)
    #expect(source.map { layout.rowText($0) } == destination.map { layout.rowText($0) })
    #expect(source.allSatisfy { layout.place(atRow: $0).side == move.source.role })
    #expect(destination.allSatisfy { layout.place(atRow: $0).side == move.destination.role })
    try expectRowsAndLinesAgree(in: layout, of: session)
  }

  @Test func changesAtTheStartAndTheEndOfTheFilesKeepTheirPlace() async throws {
    let session = try await diff("old start\na\nb\nold end", "new start\na\nb\nnew end\nmore")
    let layout = SingleColumnLayout(session: session)

    #expect(
      layout.rowDescriptions == [
        "1 - old start", "- 1 new start", "2 2 a", "3 3 b", "4 - old end", "- 4 new end",
        "- 5 more",
      ])
    try expectRowsAndLinesAgree(in: layout, of: session)
  }

  @Test func newFileShowsOnlyRightNumbersAndARemovedFileOnlyLeftOnes() async throws {
    let added = try await diff("", "a\nb\n")
    let removed = try await diff("a\nb\n", "")

    #expect(SingleColumnLayout(session: added).rowDescriptions == ["- 1 a", "- 2 b"])
    #expect(SingleColumnLayout(session: removed).rowDescriptions == ["1 - a", "2 - b"])
    try expectRowsAndLinesAgree(in: SingleColumnLayout(session: added), of: added)
    try expectRowsAndLinesAgree(in: SingleColumnLayout(session: removed), of: removed)
  }

  @Test func twoEmptyFilesHaveNoRows() async throws {
    let session = try await diff("", "")
    let layout = SingleColumnLayout(session: session)

    #expect(layout.rowCount == 0)
    #expect(layout.displayText.rowCount == 0)
  }

  @Test func unchangedRowsShowTheTextOfTheSecondSide() async throws {
    let session = try await diff("a  b\nx\n", "a b\ny\n", mode: .ignoreWhitespaceAmount)

    #expect(SingleColumnLayout(session: session).rowTexts == ["a b", "x", "y"])
    #expect(SingleColumnLayout(session: session, firstSide: .b).rowTexts == ["a  b", "y", "x"])
  }

  @Test func rowsShowLineBreaksWithinALineAsPicturesOfTheSameLength() async throws {
    let session = try await diff("one\rstill one\n", "one\rstill one\nmore\n")
    let layout = SingleColumnLayout(session: session)

    #expect(layout.rowTexts == ["one\u{240D}still one", "more"])
  }

  @Test func lineThatRulesMatchEntirelyTakesARowOfItsOwnSide() async throws {
    let stamp = IgnoreRule(name: "Build stamp", pattern: "^// built .*$")
    let session = try await diff("a\nb\n", "a\n// built 2026-11-15\nb\n", ignoring: [stamp])
    let layout = SingleColumnLayout(session: session)

    #expect(!session.blocks.contains { $0.kind == .changed })
    #expect(layout.rowDescriptions == ["1 1 a", "- 2 // built 2026-11-15", "2 3 b"])
    #expect(IgnoredDifferences(in: session).rows(on: layout) == IndexSet(integer: 1))
    try expectRowsAndLinesAgree(in: layout, of: session)
  }

  @Test func collapsedRunHidesTheSameLinesInTheColumnAsOnTheGrid() async throws {
    let unchanged = (1...12).map { "same \($0)\n" }.joined()
    let session = try await diff("old\n" + unchanged + "x\n", "new\nnewer\n" + unchanged + "y\n")
    let layout = SingleColumnLayout(session: session)
    let collapsed = CollapsedRows(session: session)
    let run = try #require(collapsed.runs.first)

    let rows = collapsed.rows(of: run, in: layout)
    #expect(rows.count == run.rows.count)
    #expect(
      rows.map { layout.place(atRow: $0).line(in: .a) }
        == Array(collapsed.lines(of: run, in: .a)))
    #expect(
      rows.map { layout.place(atRow: $0).line(in: .b) }
        == Array(collapsed.lines(of: run, in: .b)))
    #expect(rows.map { layout.rowText($0) } == (4...9).map { "same \($0)" })
  }

  @Test func targetInACollapsedRunOfTheColumnExpandsIt() async throws {
    let unchanged = (1...12).map { "same \($0)\n" }.joined()
    let session = try await diff("old\n" + unchanged, "new\nnewer\n" + unchanged)
    let layout = SingleColumnLayout(session: session)
    var collapsed = CollapsedRows(session: session)
    let run = try #require(collapsed.runs.first)
    let changedRow = layout.rows(of: try #require(session.blocks.first)).lowerBound

    let expandedForChange = collapsed.expandToShow(row: changedRow, in: layout)
    #expect(!expandedForChange)
    #expect(collapsed.runs == [run])
    let lastHiddenRow = collapsed.rows(of: run, in: layout).upperBound - 1
    let expandedForTarget = collapsed.expandToShow(row: lastHiddenRow, in: layout)
    #expect(expandedForTarget)
    #expect(collapsed.runs.isEmpty)
  }

  @Test func highlightsOfBothPartsAreThoseOfThePanesSideBySide() async throws {
    let session = try await diff("a\nlet value = 1\nb\n", "a\nlet total = 1\nb\n")
    let layout = SingleColumnLayout(session: session)
    let changed = try #require(session.blocks.first { $0.kind == .changed })
    let highlights = try session.inlineHighlights(for: changed)

    #expect(layout.highlightedTexts(highlights, in: .a) == ["value"])
    #expect(layout.highlightedTexts(highlights, in: .b) == ["total"])
    let first = layout.displayText.utf16Range(ofRow: layout.row(ofLine: 1, in: .a))
    let second = layout.displayText.utf16Range(ofRow: layout.row(ofLine: 1, in: .b))
    #expect(highlights.ranges(in: .a, on: layout).allSatisfy { first.contains($0.lowerBound) })
    #expect(highlights.ranges(in: .b, on: layout).allSatisfy { second.contains($0.lowerBound) })
  }

  @Test func removalMarkKeepsItsPlaceWithinTheLine() async throws {
    let session = try await diff("a\nlet value = compute(1, 2)\n", "a\nlet value = compute(1)\n")
    let layout = SingleColumnLayout(session: session)
    let changed = try #require(session.blocks.first { $0.kind == .changed })
    let highlights = try session.inlineHighlights(for: changed)
    let gridText = try #require(session.rowLayout.displayText(for: .b))

    let gridMarks = highlights.ranges(in: .b).filter(\.isEmpty).map {
      $0.lowerBound - gridText.utf16Range(ofRow: 1).lowerBound
    }
    let row = layout.displayText.utf16Range(ofRow: layout.row(ofLine: 1, in: .b))
    let columnMarks = highlights.ranges(in: .b, on: layout).filter(\.isEmpty).map {
      $0.lowerBound - row.lowerBound
    }
    #expect(!gridMarks.isEmpty)
    #expect(columnMarks == gridMarks)
  }

  @Test func sharedRowWhoseFirstSideDiffersKeepsItsMarkAndShowsThePlacesOfTheSecond() async throws {
    let session = try await diff(
      "a\tb\nc\nkeep\n", "a b\nc  \nkeep\n", mode: .ignoreWhitespaceAmount)
    let layout = SingleColumnLayout(session: session)
    let ignored = IgnoredDifferences(in: session)

    #expect(layout.rowDescriptions == ["1 1 a b", "2 2 c  ", "3 3 keep"])
    #expect(ignored.rows(on: layout) == IndexSet([0, 1]))
    let places = try ignored.places(on: layout, of: session)
    #expect(places.map { layout.displayText.string.utf16Substring($0) } == [" ", "  "])
    #expect(places.map { layout.displayText.row(containing: $0.lowerBound) } == [0, 1])
  }

  @Test func sharedRowWhoseSecondSideOnlyLacksWhitespaceKeepsItsMarkWithoutPlaces() async throws {
    let session = try await diff("c  \nkeep\n", "c\nkeep\n", mode: .ignoreWhitespaceAmount)
    let layout = SingleColumnLayout(session: session)
    let ignored = IgnoredDifferences(in: session)

    #expect(ignored.rows(on: layout) == IndexSet(integer: 0))
    #expect(try ignored.places(on: layout, of: session).isEmpty)
  }

  /// Random comparisons, seed 29, with and without a rule that matches lines entirely, against a
  /// layout built the obvious way, row by row.
  @Test(arguments: [ComparisonMode.exact, .ignoreWhitespaceAmount])
  func rowsFollowTheBlocksInRandomComparisons(mode: ComparisonMode) async throws {
    var generator = SplitMix64(seed: 29)
    for round in 0..<300 {
      let old = Self.randomText(using: &generator)
      let new = Self.randomText(using: &generator)
      let stamp = IgnoreRule(name: "Build stamp", pattern: "^// built .*$")
      let rules = round.isMultiple(of: 2) ? [] : [stamp]
      let session = try await diff(old, new, mode: mode, ignoring: rules)
      for firstSide in [Role.a, .b] {
        let layout = SingleColumnLayout(session: session, firstSide: firstSide)
        let expected = Self.expectedRows(of: session, firstSide: firstSide)
        #expect(
          (0..<layout.rowCount).map { Self.lines(of: layout.place(atRow: $0)) } == expected,
          "Round \(round): \(old.debugDescription) against \(new.debugDescription)")
        try expectRowsAndLinesAgree(in: layout, of: session)
        for block in session.blocks where block.kind == .changed {
          let highlights = try session.inlineHighlights(for: block)
          for role in [Role.a, .b] {
            #expect(
              layout.highlightedTexts(highlights, in: role)
                == (try session.highlightedTexts(highlights, in: role)),
              "Round \(round): \(old.debugDescription) against \(new.debugDescription)")
          }
        }
      }
    }
  }

  /// A text of a few lines from a small vocabulary, with whitespace variants, lines that the rule
  /// matches entirely and sometimes no final line ending.
  private static func randomText(using generator: inout SplitMix64) -> String {
    let vocabulary = [
      "x", "y", "z", "x  y", "x y", "let value = 1", "let total = 1", "", "// built 1",
    ]
    let lines = (0..<Int.random(in: 0...7, using: &generator)).map { _ in
      vocabulary.randomElement(using: &generator) ?? ""
    }
    let text = lines.joined(separator: "\n")
    return Bool.random(using: &generator) && !lines.isEmpty ? text + "\n" : text
  }

  /// The lines of A and B of each row, built block by block: pairs of lines of an unchanged
  /// block, then the lines of the first side, then those of the second.
  private static func expectedRows(of session: Session, firstSide: Role) -> [[Int?]] {
    let secondSide: Role = firstSide == .a ? .b : .a
    var rows: [[Int?]] = []
    func row(_ line: Int?, of role: Role, and other: Int?) -> [Int?] {
      role == .a ? [line, other] : [other, line]
    }
    for block in session.blocks {
      let first = Array(block.lines(in: firstSide))
      let second = Array(block.lines(in: secondSide))
      let shared = block.kind == .unchanged ? min(first.count, second.count) : 0
      for index in 0..<shared {
        rows.append(row(first[index], of: firstSide, and: second[index]))
      }
      for line in first.dropFirst(shared) {
        rows.append(row(line, of: firstSide, and: nil))
      }
      for line in second.dropFirst(shared) {
        rows.append(row(line, of: secondSide, and: nil))
      }
    }
    return rows
  }

  private static func lines(of place: SingleColumnLayout.Place) -> [Int?] {
    [place.line(in: .a), place.line(in: .b)]
  }
}

/// Checks that every row maps to its lines and back, that every line of each side maps to a row
/// that shows it, that each row shows the text of a line it names, and that each row belongs to
/// the block whose rows contain it.
private func expectRowsAndLinesAgree(
  in layout: SingleColumnLayout, of session: Session,
  sourceLocation: SourceLocation = #_sourceLocation
) throws {
  #expect(layout.displayText.rowCount == layout.rowCount, sourceLocation: sourceLocation)
  let lineTexts = [Role.a: try session.lineTexts(of: .a), .b: try session.lineTexts(of: .b)]
  for row in 0..<layout.rowCount {
    let place = layout.place(atRow: row)
    #expect(layout.rows(of: place.block).contains(row), sourceLocation: sourceLocation)
    let lines = [Role.a, .b].compactMap { role in place.line(in: role).map { (role, $0) } }
    #expect(!lines.isEmpty, sourceLocation: sourceLocation)
    for (role, line) in lines {
      #expect(layout.row(ofLine: line, in: role) == row, sourceLocation: sourceLocation)
      #expect(place.block.lines(in: role).contains(line), sourceLocation: sourceLocation)
    }
    if let side = place.side {
      #expect(lines.count == 1, sourceLocation: sourceLocation)
      #expect(
        layout.rows(of: place.block, showingOnly: side).contains(row),
        sourceLocation: sourceLocation)
    }
    let shown = place.line(in: place.side ?? (layout.firstSide == .a ? .b : .a))
    #expect(
      shown.flatMap { lineTexts[place.side ?? (layout.firstSide == .a ? .b : .a)]?[$0] }
        == layout.rowText(row), sourceLocation: sourceLocation)
  }
  for role in [Role.a, .b] {
    for line in 0..<session.rowLayout.lineCount(in: role) {
      #expect(
        layout.place(atRow: layout.row(ofLine: line, in: role)).line(in: role) == line,
        sourceLocation: sourceLocation)
    }
  }
}

extension SingleColumnLayout {
  /// The text of `row`.
  fileprivate func rowText(_ row: Int) -> String {
    displayText.string.utf16Substring(displayText.utf16Range(ofRow: row))
  }

  /// The text of each row.
  fileprivate var rowTexts: [String] {
    (0..<rowCount).map(rowText)
  }

  /// Each row as its line number on the left, on the right, and its text, with `-` for a side
  /// whose line the row does not show.
  fileprivate var rowDescriptions: [String] {
    (0..<rowCount).map { row in
      let place = place(atRow: row)
      let numbers = [Role.a, .b].map { place.line(in: $0).map { String($0 + 1) } ?? "-" }
      return (numbers + [rowText(row)]).joined(separator: " ")
    }
  }

  /// The highlighted texts of `role` in the column, without the removal marks.
  fileprivate func highlightedTexts(_ highlights: InlineHighlights, in role: Role) -> [String] {
    highlights.ranges(in: role, on: self).filter { !$0.isEmpty }.map {
      displayText.string.utf16Substring($0)
    }
  }
}

extension DisplayText {
  /// The row whose text or separator holds the UTF-16 offset `offset`.
  fileprivate func row(containing offset: Int) -> Int? {
    (0..<rowCount).first {
      utf16Range(ofRow: $0).lowerBound <= offset
        && offset <= utf16Range(ofRow: $0).upperBound
    }
  }
}

extension Session {
  /// The highlighted texts of `role` on its pane side by side, without the removal marks.
  fileprivate func highlightedTexts(
    _ highlights: InlineHighlights, in role: Role
  ) throws -> [String] {
    let string = try displayString(of: role)
    return highlights.ranges(in: role).filter { !$0.isEmpty }.map { string.utf16Substring($0) }
  }
}
