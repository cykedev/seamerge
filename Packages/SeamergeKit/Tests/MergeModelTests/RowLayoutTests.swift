import MergeModel
import Testing

struct RowLayoutTests {
  /// A merge with every kind of block, each with ranges of different lengths.
  static let base = "keep 1\nonly a\nkeep 2\nonly b\nkeep 3\nboth\nkeep 4\nconflict\nkeep 5\n"
  static let a =
    "keep 1\nonly a, changed\nand a line more\nkeep 2\nonly b\nkeep 3\nboth, changed\nkeep 4\n"
    + "conflict in a\nkeep 5\nadded by a\n"
  static let b =
    "keep 1\nonly a\nkeep 2\nkeep 3\nboth, changed\nkeep 4\nconflict in b\nwith a line more\n"
    + "and another\nkeep 5\n"

  @Test func mergeHasEveryKindOfBlock() async throws {
    let session = try await merge(base: Self.base, a: Self.a, b: Self.b)

    let kinds = Set(session.blocks.map(\.kind))
    #expect(kinds == [.unchanged, .changedInA, .changedInB, .changedInBoth, .conflict])
  }

  @Test func layoutThatLetGoOfItsTextsLaysThemOutAlikeWhenAsked() async throws {
    let session = try await merge(base: Self.base, a: Self.a, b: Self.b)
    let layout = session.rowLayout
    let texts = session.roles.map { layout.displayText(for: $0)?.string }

    layout.letGoOfDisplayTexts()

    #expect(session.roles.map { layout.displayText(for: $0)?.string } == texts)
    #expect(session.roles.map { session.rowLayout.displayText(for: $0)?.string } == texts)
    #expect(layout.displayText(for: .base)?.utf16Range(ofRow: 0) == 0..<6)
  }

  @Test func rowsAndLinesMapToEachOtherInEveryKindOfBlock() async throws {
    let session = try await merge(base: Self.base, a: Self.a, b: Self.b)

    try expectRowsAndLinesAgree(in: session)
  }

  @Test func rowsAndLinesMapToEachOtherInAComparison() async throws {
    let session = try await diff("a\nb\nc\nd\n", "a\nB\nB2\nc\nnew\n")

    #expect(Set(session.blocks.map(\.kind)) == [.unchanged, .changed])
    try expectRowsAndLinesAgree(in: session)
  }

  @Test func rowsAndLinesMapToEachOtherWithoutABase() async throws {
    let session = try await merge(base: nil, a: "same\nonly a\nsame 2\n", b: "same\nsame 2\nb\n")

    #expect(session.rowLayout.lineCount(in: .base) == 0)
    try expectRowsAndLinesAgree(in: session)
  }

  @Test func blockTakesTheRowsOfItsLongestSideAndOthersGetFillerRows() async throws {
    let session = try await merge(base: Self.base, a: Self.a, b: Self.b)
    let conflict = try #require(session.blocks.first { $0.kind == .conflict })
    let rows = session.rowLayout.rows(of: conflict)

    #expect(rows.count == 3)
    #expect(rows.map { session.rowLayout.line(atRow: $0, in: .b) } == [6, 7, 8])
    #expect(rows.map { session.rowLayout.line(atRow: $0, in: .a) } == [8, nil, nil])
    #expect(rows.map { session.rowLayout.line(atRow: $0, in: .base) } == [7, nil, nil])
    #expect(rows.allSatisfy { session.rowLayout.block(atRow: $0) == conflict })
  }

  @Test func everyBlockStartsOnTheSameRowInEveryPane() async throws {
    let session = try await merge(base: Self.base, a: Self.a, b: Self.b)

    for block in session.blocks {
      let firstRow = session.rowLayout.rows(of: block).lowerBound
      for role in Role.allCases where !block.lines(in: role).isEmpty {
        #expect(
          session.rowLayout.row(ofLine: block.lines(in: role).lowerBound, in: role) == firstRow)
      }
    }
  }

  @Test func displayTextOfEveryRoleHasOneLinePerRow() async throws {
    let session = try await merge(base: Self.base, a: Self.a, b: Self.b)

    for role in session.roles {
      let lines = try session.displayString(of: role).split(
        separator: "\n", omittingEmptySubsequences: false)
      #expect(lines.count == session.rowLayout.rowCount)
      #expect(try session.rowTexts(of: role).count == session.rowLayout.rowCount)
    }
  }

  @Test func displayTextShowsLinesWithoutLineEndingsAndFillerRowsEmpty() async throws {
    let session = try await diff("one\r\ntwo\r\nthree", "one\r\nthree")

    #expect(try session.rowTexts(of: .a) == ["one", "two", "three"])
    #expect(try session.rowTexts(of: .b) == ["one", "", "three"])
    #expect(try session.displayString(of: .b) == "one\n\nthree")
  }

  @Test func rowRangeLiesOnTheTextOfItsLine() async throws {
    let session = try await diff("Grüße 😀\n東京\n", "Grüße 😀\n大阪\n")
    let text = try #require(session.rowLayout.displayText(for: .b))

    #expect(text.utf16Range(ofRow: 0) == 0..<8)
    #expect(text.utf16Range(ofRow: 1) == 9..<11)
  }

  @Test func carriageReturnWithinALineIsShownAsAPictureInExactMode() async throws {
    let session = try await diff("a\rb\nc\n", "a\rb\nd\n")

    #expect(session.rowLayout.lineCount(in: .a) == 2)
    #expect(try session.rowTexts(of: .a) == ["a\u{240D}b", "c"])
  }

  @Test func loneCarriageReturnEndsALineWhenLineEndingsAreIgnored() async throws {
    let session = try await diff("a\rb\nc\n", "a\rb\nd\n", mode: .ignoreLineEndings)

    #expect(session.rowLayout.lineCount(in: .a) == 3)
    #expect(try session.rowTexts(of: .a) == ["a", "b", "c"])
  }

  @Test func otherLineBreakingCharactersAreShownAsAPicture() async throws {
    let session = try await diff("a\u{2028}b\u{2029}c\u{85}d\n", "x\n")

    #expect(try session.rowTexts(of: .a) == ["a\u{2424}b\u{2424}c\u{2424}d"])
  }

  @Test func emptyFilesHaveNoRows() async throws {
    let session = try await merge(base: "", a: "", b: "")

    #expect(session.blocks.isEmpty)
    #expect(session.rowLayout.rowCount == 0)
    #expect(try session.displayString(of: .a) == "")
  }

  /// Checks that each row and the line it shows map to each other, for every role.
  private func expectRowsAndLinesAgree(in session: Session) throws {
    let layout = session.rowLayout
    for role in Role.allCases {
      var shownLines: [Int] = []
      for row in 0..<layout.rowCount {
        guard let line = layout.line(atRow: row, in: role) else { continue }
        #expect(layout.row(ofLine: line, in: role) == row)
        shownLines.append(line)
      }
      #expect(shownLines == Array(0..<layout.lineCount(in: role)))
    }
    for block in session.blocks {
      for row in layout.rows(of: block) {
        #expect(layout.block(atRow: row) == block)
      }
    }
  }
}

/// The text of a side without filler rows, as a pane shows it that connects its changes to its
/// neighbors.
struct LineTextTests {
  @Test func lineTextShowsEveryLineOnARowOfItsOwnWithoutFillerRows() async throws {
    let session = try await diff("a\nb\nc\nd\n", "a\nB\nB2\nc\nnew\n")
    let layout = session.rowLayout

    for role in [Role.a, .b] {
      let text = try #require(layout.lineText(for: role))
      let rows = (0..<text.rowCount).map { text.string.utf16Substring(text.utf16Range(ofRow: $0)) }
      #expect(text.rowCount == layout.lineCount(in: role))
      #expect(rows.allSatisfy { !$0.isEmpty })
    }
    #expect(try #require(layout.lineText(for: .a)).string == "a\nb\nc\nd")
    #expect(try #require(layout.lineText(for: .b)).string == "a\nB\nB2\nc\nnew")
    #expect(layout.lineText(for: .base) == nil)
  }

  @Test func lineTextShowsLineBreakingCharactersAsPicturesLikeTheGrid() async throws {
    let session = try await diff("a\u{2028}b\n", "x\n")

    #expect(try #require(session.rowLayout.lineText(for: .a)).string == "a\u{2424}b")
  }

  @Test func lineTextOfAnEmptyFileHasNoRows() async throws {
    let session = try await diff("", "a\n")

    #expect(try #require(session.rowLayout.lineText(for: .a)).rowCount == 0)
    #expect(try #require(session.rowLayout.lineText(for: .a)).string == "")
  }
}
