import MergeModel
import Testing

struct InlineHighlightsTests {
  @Test func changedWordsAreHighlightedOnBothSidesOfAComparison() async throws {
    let session = try await diff("Grüße aus Köln 🙂\n", "Grüße aus Zürich 🙃\n")

    #expect(try session.highlightedTexts(of: .a, inFirst: .changed) == ["Köln", "🙂"])
    #expect(try session.highlightedTexts(of: .b, inFirst: .changed) == ["Zürich", "🙃"])
  }

  @Test func highlightsLieOnCJKCharacters() async throws {
    let session = try await diff("駅は 東京 です\n", "駅は 大阪 です\n")

    #expect(try session.highlightedTexts(of: .a, inFirst: .changed) == ["東京"])
    #expect(try session.highlightedTexts(of: .b, inFirst: .changed) == ["大阪"])
  }

  @Test func manyChangesWithinOneLineLieOnTheirCharacters() async throws {
    let old = (0..<200).map { "ü😀 v\($0) 東" }.joined(separator: " ") + "\n"
    let new = (0..<200).map { "ü😀 v\($0 + 1_000) 東" }.joined(separator: " ") + "\n"
    let session = try await diff(old, new)

    #expect(
      try session.highlightedTexts(of: .a, inFirst: .changed) == (0..<200).map { "v\($0)" })
    #expect(
      try session.highlightedTexts(of: .b, inFirst: .changed)
        == (0..<200).map { "v\($0 + 1_000)" })
  }

  @Test func highlightsAreOffsetByTheRowsAboveIncludingFillerRows() async throws {
    let session = try await diff(
      "same\nnot in b\nvalue = 1 // 😀 ü\n", "same\nvalue = 2 // 😀 ü\n")
    let block = try #require(session.blocks.first { $0.kind == .changed })
    let ranges = try session.inlineHighlights(for: block).ranges(in: .b)
    let text = try #require(session.rowLayout.displayText(for: .b))

    #expect(ranges.map { text.string.utf16Substring($0) } == ["2"])
    #expect(ranges.first?.lowerBound == text.utf16Range(ofRow: 1).lowerBound + 8)
  }

  @Test func highlightsLieOnTheExpectedCharactersOfAFileEndingInCR() async throws {
    let session = try await diff("eins\rzwei 😀 ü\rdrei\r", "eins\rzwei 🙃 ü\rdrei\r")
    let block = try #require(session.blocks.first { $0.kind == .changed })
    let ranges = try session.inlineHighlights(for: block).ranges(in: .a)
    let text = try #require(session.rowLayout.displayText(for: .a))

    #expect(ranges.map { text.string.utf16Substring($0) } == ["😀"])
    #expect(ranges.first?.lowerBound == text.utf16Range(ofRow: 1).lowerBound + 5)
    #expect(try session.highlightedTexts(of: .b, inFirst: .changed) == ["🙃"])
  }

  @Test func mergeHighlightsEachSideAgainstTheBaseAndNeverTheBase() async throws {
    let session = try await merge(
      base: "let size = 10 // 📏\n", a: "let size = 12 // 📏\n", b: "let width = 10 // 📏\n")

    #expect(try session.highlightedTexts(of: .a, inFirst: .conflict) == ["12"])
    #expect(try session.highlightedTexts(of: .b, inFirst: .conflict) == ["width"])
    #expect(try session.highlightedTexts(of: .base, inFirst: .conflict).isEmpty)
  }

  @Test func sideThatDidNotChangeTheBlockHasNoHighlights() async throws {
    let session = try await merge(base: "x = 1;\n", a: "x = 2;\n", b: "x = 1;\n")

    #expect(try session.highlightedTexts(of: .a, inFirst: .changedInA) == ["2"])
    #expect(try session.highlightedTexts(of: .b, inFirst: .changedInA).isEmpty)
  }

  @Test func unchangedBlockHasNoHighlights() async throws {
    let session = try await diff("same\n", "same\n")
    let block = try #require(session.blocks.first)

    #expect(try session.inlineHighlights(for: block).isEmpty)
  }

  @Test func mergeWithoutABaseHighlightsAAgainstBInBothPanes() async throws {
    let session = try await merge(base: nil, a: "x = 1; // ä 😀\n", b: "x = 2; // ä 😀\n")
    let block = try #require(session.blocks.first)
    let highlights = try session.inlineHighlights(for: block)

    #expect(block.kind != .unchanged)
    #expect(
      try highlights.ranges(in: .a).map { try session.displayString(of: .a).utf16Substring($0) }
        == ["1"])
    #expect(
      try highlights.ranges(in: .b).map { try session.displayString(of: .b).utf16Substring($0) }
        == ["2"])
  }

  @Test func mergeComparingTheSidesHighlightsAAgainstBWhicheverSideChanged() async throws {
    let session = try await merge(
      base: "x = 1;\nkeep\ny = 1;\nkeep\nz = 1;\nkeep\nw = 1;\n",
      a: "x = 2;\nkeep\ny = 1;\nkeep\nz = 3;\nkeep\nw = 5;\n",
      b: "x = 1;\nkeep\ny = 2;\nkeep\nz = 4;\nkeep\nw = 5;\n")
    func texts(of role: Role, in kind: Block.Kind) throws -> [String] {
      let block = try #require(session.blocks.first { $0.kind == kind })
      let text = try session.displayString(of: role)
      return try session.inlineHighlights(for: block, comparingSides: true).ranges(in: role)
        .map { text.utf16Substring($0) }
    }

    // A changed x, B changed y: each side shows where it differs from the other.
    #expect(try texts(of: .a, in: .changedInA) == ["2"])
    #expect(try texts(of: .b, in: .changedInA) == ["1"])
    #expect(try texts(of: .a, in: .changedInB) == ["1"])
    #expect(try texts(of: .b, in: .changedInB) == ["2"])
    #expect(try texts(of: .a, in: .conflict) == ["3"])
    #expect(try texts(of: .b, in: .conflict) == ["4"])
    // Both changed w alike: the sides do not differ.
    let same = try #require(session.blocks.first { $0.kind == .changedInBoth })
    #expect(try session.inlineHighlights(for: same, comparingSides: true).isEmpty)
    #expect(try !session.inlineHighlights(for: same).isEmpty)
    #expect(try texts(of: .base, in: .conflict).isEmpty)
  }

  @Test func changeSpanningALineBreakIsHighlightedPerLineWithoutTheLineEnding() async throws {
    let session = try await diff("one two\nend\n", "one\nTWO two\nend\n")

    #expect(try session.highlightedTexts(of: .b, inFirst: .changed) == ["TWO"])
  }

  @Test func blockTextIsComparedAsAWholeAcrossInsertedLines() async throws {
    let session = try await diff("let a = 1\nlet b = 2\n", "let a = 10\n// note\nlet b = 20\n")

    #expect(try session.highlightedTexts(of: .b, inFirst: .changed) == ["10", "// note", "20"])
  }

  @Test func sixtyPercentChangedRunsAreStillHighlighted() async throws {
    let session = try await diff("a,b,c", "x;y,c")

    #expect(try session.highlightedTexts(of: .a, inFirst: .changed) == ["a,b"])
    #expect(try session.highlightedTexts(of: .b, inFirst: .changed) == ["x;y"])
  }

  @Test func moreThanSixtyPercentChangedRunsAreNotHighlighted() async throws {
    let session = try await diff("a,b,c", "x;y;c")
    let block = try #require(session.blocks.first)

    #expect(try session.inlineHighlights(for: block).isEmpty)
  }

  @Test func insertedLinesAreNotHighlighted() async throws {
    let session = try await diff("a\n", "a\nb\n")
    let block = try #require(session.blocks.first { $0.kind == .changed })

    #expect(try session.inlineHighlights(for: block).isEmpty)
  }

  @Test func highlightIsWidenedToTheWholeComposedCharacter() async throws {
    let session = try await diff("key #\u{FE0F}\u{20E3} on\n", "key *\u{FE0F}\u{20E3} on\n")

    #expect(try session.highlightedTexts(of: .a, inFirst: .changed) == ["#\u{FE0F}\u{20E3}"])
    #expect(try session.highlightedTexts(of: .b, inFirst: .changed) == ["*\u{FE0F}\u{20E3}"])
  }

  @Test func changedAmountOfWhitespaceIsHighlightedOnlyInExactMode() async throws {
    let old = "a  = 1;\n"
    let new = "a = 10;\n"

    let exact = try await diff(old, new)
    #expect(try exact.highlightedTexts(of: .b, inFirst: .changed) == [" ", "10"])

    for mode in [ComparisonMode.ignoreWhitespaceAmount, .ignoreAllWhitespace] {
      let ignoring = try await diff(old, new, mode: mode)
      #expect(try ignoring.highlightedTexts(of: .b, inFirst: .changed) == ["10"])
    }
  }

  @Test func trailingWhitespaceIsHighlightedUnlessTheModeIgnoresIt() async throws {
    let old = "a 1  \n"
    let new = "b 1\n"

    let exact = try await diff(old, new)
    #expect(try exact.highlightedTexts(of: .a, inFirst: .changed) == ["a", "  "])

    let ignoring = try await diff(old, new, mode: .ignoreWhitespaceAmount)
    #expect(try ignoring.highlightedTexts(of: .a, inFirst: .changed) == ["a"])
  }

  @Test func addedSpaceWithinALineCountsUnlessAllWhitespaceIsIgnored() async throws {
    let old = "f(a,b) c\n"
    let new = "f(a, b) d\n"

    let amount = try await diff(old, new, mode: .ignoreWhitespaceAmount)
    #expect(try amount.highlightedTexts(of: .b, inFirst: .changed) == [" ", "d"])

    let all = try await diff(old, new, mode: .ignoreAllWhitespace)
    #expect(try all.highlightedTexts(of: .b, inFirst: .changed) == ["d"])
  }

  @Test func spaceReplacedByALineBreakIsHighlightedInEveryMode() async throws {
    for mode in ComparisonMode.allCases {
      let session = try await diff("a b\nx\n", "a\nb\nx\n", mode: mode)

      #expect(try session.highlightedTexts(of: .a, inFirst: .changed) == [" "], "\(mode)")
    }
  }

  @Test func changedLineEndingCountsTowardsTheLimitOnlyInExactMode() async throws {
    let exact = try await diff("a.x\r\n", "b,x\n")
    let exactBlock = try #require(exact.blocks.first)
    #expect(try exact.inlineHighlights(for: exactBlock).isEmpty)

    let ignoring = try await diff("a.x\r\n", "b,x\n", mode: .ignoreLineEndings)
    #expect(try ignoring.highlightedTexts(of: .a, inFirst: .changed) == ["a."])
    #expect(try ignoring.highlightedTexts(of: .b, inFirst: .changed) == ["b,"])
  }
}
