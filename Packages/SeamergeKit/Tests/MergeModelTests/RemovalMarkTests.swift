import Foundation
import MergeModel
import Testing

struct RemovalMarkTests {
  @Test func removalWithinAnIdentifierIsMarkedBetweenItsRemainingParts() async throws {
    let session = try await diff("let user-old.name = 1\n", "let user.name = 1\n")

    #expect(try session.removalMarks(of: .b, inFirst: .changed) == [8])
    #expect(try session.highlightedTexts(of: .b, inFirst: .changed).isEmpty)
    #expect(try session.highlightedTexts(of: .a, inFirst: .changed) == ["-old"])
    #expect(try session.removalMarks(of: .a, inFirst: .changed).isEmpty)
  }

  @Test func removalAtTheStartOfALineIsMarkedAtTheStartOfItsRow() async throws {
    let session = try await diff("same\nold value = 1\n", "same\nvalue = 1\n")
    let text = try #require(session.rowLayout.displayText(for: .b))

    #expect(
      try session.removalMarks(of: .b, inFirst: .changed) == [text.utf16Range(ofRow: 1).lowerBound])
  }

  @Test func removalAtTheEndOfALineIsMarkedAtTheEndOfItsRow() async throws {
    let session = try await diff("x = 1; // done\n", "x = 1;\n")
    let text = try #require(session.rowLayout.displayText(for: .b))

    #expect(
      try session.removalMarks(of: .b, inFirst: .changed) == [text.utf16Range(ofRow: 0).upperBound])
  }

  @Test func removalThatLeavesAnEmptyLineIsMarkedInIt() async throws {
    let session = try await diff("a\nfoo\nb\n", "a\n\nb\n")
    let text = try #require(session.rowLayout.displayText(for: .b))

    #expect(text.utf16Range(ofRow: 1).isEmpty)
    #expect(
      try session.removalMarks(of: .b, inFirst: .changed) == [text.utf16Range(ofRow: 1).lowerBound])
  }

  @Test func removalAfterUmlautsAndAnEmojiIsMarkedAtItsUTF16Position() async throws {
    let session = try await diff("Grüße 🙂 aus Köln!\n", "Grüße 🙂 aus!\n")

    #expect(try session.removalMarks(of: .b, inFirst: .changed) == ["Grüße 🙂 aus".utf16.count])
    #expect(try session.highlightedTexts(of: .a, inFirst: .changed) == [" Köln"])
  }

  @Test func removalWithinAComposedCharacterIsMarkedAtItsStart() async throws {
    let session = try await diff("key # \u{FE0F}\u{20E3} on\n", "key #\u{FE0F}\u{20E3} on\n")

    #expect(try session.removalMarks(of: .b, inFirst: .changed) == [4])
  }

  @Test func whitespaceRemovedWithinALineIsMarkedUnlessAllWhitespaceIsIgnored() async throws {
    for mode in ComparisonMode.allCases {
      let session = try await diff("f(a, b) c\n", "f(a,b) d\n", mode: mode)
      let expected = mode == .ignoreAllWhitespace ? [] : [4]

      #expect(try session.removalMarks(of: .b, inFirst: .changed) == expected, "\(mode)")
      #expect(try session.highlightedTexts(of: .b, inFirst: .changed) == ["d"], "\(mode)")
    }
  }

  @Test func trailingWhitespaceRemovedIsMarkedUnlessTheModeIgnoresIt() async throws {
    for mode in ComparisonMode.allCases {
      let session = try await diff("a 1  \n", "b 1\n", mode: mode)
      let ignores = mode == .ignoreWhitespaceAmount || mode == .ignoreAllWhitespace

      #expect(
        try session.removalMarks(of: .b, inFirst: .changed) == (ignores ? [] : [3]), "\(mode)")
    }
  }

  @Test func mergeMarksEachSideAgainstTheBaseAndNeverTheBase() async throws {
    let session = try await merge(
      base: "let size = 10 // max\n", a: "let size = 10\n", b: "let size = 10 // max!\n")

    #expect(try session.removalMarks(of: .a, inFirst: .conflict) == [13])
    #expect(try session.removalMarks(of: .b, inFirst: .conflict).isEmpty)
    #expect(try session.highlightedTexts(of: .b, inFirst: .conflict) == ["!"])
    #expect(try session.inlineRanges(of: .base, inFirst: .conflict).isEmpty)
  }

  @Test func comparisonMarksEachSideWhereItLacksTheOthersText() async throws {
    let session = try await diff("first, second\n", "first second!\n")

    #expect(try session.inlineRanges(of: .a, inFirst: .changed) == [5..<6, 13..<13])
    #expect(try session.inlineRanges(of: .b, inFirst: .changed) == [5..<5, 12..<13])
    try expectPaneContract(session, roles: [.a, .b])
  }

  @Test func mergeWithoutABaseMarksAAgainstBInBothPanes() async throws {
    let session = try await merge(base: nil, a: "first, second\n", b: "first second!\n")
    let block = try #require(session.blocks.first)
    let highlights = try session.inlineHighlights(for: block)

    #expect(block.kind != .unchanged)
    #expect(highlights.ranges(in: .a) == [5..<6, 13..<13])
    #expect(highlights.ranges(in: .b) == [5..<5, 12..<13])
  }

  @Test func replacedTextIsHighlightedWithoutARemovalMark() async throws {
    let session = try await diff("x = 1 // ä\n", "x = 22 // ä\n")

    #expect(try session.inlineRanges(of: .a, inFirst: .changed) == [4..<5])
    #expect(try session.inlineRanges(of: .b, inFirst: .changed) == [4..<6])
  }

  @Test func removedWholeLinesAreNotMarked() async throws {
    let old = "x = 1;\nremoved line\ny = 2;\n"
    let new = "x = 10;\ny = 2;\n"

    let comparison = try await diff(old, new)
    #expect(try comparison.inlineRanges(of: .b, inFirst: .changed) == [4..<6])

    let merge = try await merge(base: old, a: new, b: old)
    #expect(try merge.inlineRanges(of: .a, inFirst: .changedInA) == [4..<6])
  }

  @Test func removalSpanningALineBreakIsMarkedOnceWhereTheTextIsMissing() async throws {
    let session = try await diff("x=alpha+\nbeta;\n", "x=beta;\n")

    #expect(try session.removalMarks(of: .b, inFirst: .changed) == [2])
    #expect(try session.highlightedTexts(of: .a, inFirst: .changed) == ["alpha+"])
  }

  @Test func joinedLinesAreMarkedWhereTheLineBreakWasRemoved() async throws {
    let session = try await diff("a;\nb\n", "a;b\n")

    #expect(try session.removalMarks(of: .b, inFirst: .changed) == [2])
    #expect(try session.inlineRanges(of: .a, inFirst: .changed).isEmpty)
  }

  @Test func missingLineEndingAtTheEndOfTheFileIsMarkedAfterTheLastCharacter() async throws {
    let session = try await diff("a\n", "a")

    #expect(try session.removalMarks(of: .b, inFirst: .changed) == [1])
  }

  @Test func removalsCountTowardsTheSixtyPercentLimit() async throws {
    let atLimit = try await diff("a, b", "b")
    #expect(try atLimit.removalMarks(of: .b, inFirst: .changed) == [0])
    #expect(try atLimit.highlightedTexts(of: .a, inFirst: .changed) == ["a, "])

    let overLimit = try await diff("a,b,c", "c")
    let block = try #require(overLimit.blocks.first)
    #expect(try overLimit.inlineHighlights(for: block).isEmpty)
  }

  /// Checks the ranges of `roles` against what a pane expects: sorted UTF-16 ranges within its
  /// text, without overlap, empty ones at the start of a composed character or the end of a row.
  private func expectPaneContract(_ session: Session, roles: [Role]) throws {
    for role in roles {
      let string = try session.displayString(of: role) as NSString
      for block in session.blocks {
        let ranges = try session.inlineHighlights(for: block).ranges(in: role)
        for (range, next) in zip(ranges, ranges.dropFirst()) {
          #expect(
            range.upperBound < next.lowerBound
              || (range.isEmpty && range.upperBound == next.lowerBound && !next.isEmpty), "\(role)")
        }
        for mark in ranges where mark.isEmpty {
          #expect(mark.lowerBound <= string.length, "\(role)")
          if mark.lowerBound < string.length {
            #expect(
              string.rangeOfComposedCharacterSequence(at: mark.lowerBound).location
                == mark.lowerBound, "\(role)")
          }
        }
      }
    }
  }
}
