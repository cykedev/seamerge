import Foundation
import MergeModel
import Testing

struct RuleIgnoredLinesTests {
  static let date = IgnoreRule(name: "Build date", pattern: #"\d{4}-\d{2}-\d{2}"#)
  static let stamp = IgnoreRule(name: "Build stamp", pattern: "^// built .*$")

  /// The kinds of the blocks of `session` with their lines in A and B.
  static func blocks(of session: Session) -> [String] {
    session.blocks.map { "\($0.kind) \($0.a) \($0.b)" }
  }

  @Test(arguments: ComparisonMode.allCases)
  func insertedLineThatRulesMatchEntirelyDoesNotCount(mode: ComparisonMode) async throws {
    let session = try await diff(
      "a\nb\n", "a\n// built 2026-11-15\nb\n", mode: mode, ignoring: [Self.stamp])

    #expect(!session.blocks.contains { $0.kind == .changed })
    #expect(
      Self.blocks(of: session) == [
        "unchanged 0..<1 0..<1", "unchanged 1..<1 1..<2",
        "unchanged 1..<2 2..<3",
      ])
    let ignored = IgnoredDifferences(in: session)
    #expect(ignored.lines(in: .b) == IndexSet(integer: 1))
    #expect(ignored.lines(in: .a).isEmpty)
    #expect(ignored.includesDifferencesThatRulesIgnore)
  }

  @Test func removedLineThatRulesMatchEntirelyDoesNotCount() async throws {
    let session = try await diff("// built 2026-01-01\na\n", "a\n", ignoring: [Self.stamp])

    #expect(Self.blocks(of: session) == ["unchanged 0..<1 0..<0", "unchanged 1..<2 0..<1"])
    #expect(IgnoredDifferences(in: session).lines(in: .a) == IndexSet(integer: 0))
  }

  @Test func insertedBlankLineStillCounts() async throws {
    let session = try await diff(
      "a\n// built 2026-01-01\nb\n", "a\n// built 2026-11-15\n\nb\n", ignoring: [Self.stamp])

    #expect(
      Self.blocks(of: session) == [
        "unchanged 0..<2 0..<2", "changed 2..<2 2..<3",
        "unchanged 2..<3 3..<4",
      ])
  }

  @Test(arguments: ComparisonMode.allCases)
  func matchedLineThatABlankLineReplacedIsAChange(mode: ComparisonMode) async throws {
    let session = try await diff(
      "a\n// built 2026-01-01\nb\n", "a\n\nb\n", mode: mode, ignoring: [Self.stamp])

    #expect(
      Self.blocks(of: session) == [
        "unchanged 0..<1 0..<1", "unchanged 1..<2 1..<1", "changed 2..<2 1..<2",
        "unchanged 2..<3 2..<3",
      ])
  }

  @Test(arguments: ComparisonMode.allCases)
  func whitespaceLeftOverCountsOnlyWhereTheModeIgnoresIt(mode: ComparisonMode) async throws {
    let session = try await diff(
      "a\nb\n", "a\n\t  2026-11-15 \nb\n", mode: mode, ignoring: [Self.date])

    let ignoresWhitespace = mode == .ignoreWhitespaceAmount || mode == .ignoreAllWhitespace
    #expect(session.blocks.contains { $0.kind == .changed } == !ignoresWhitespace)
  }

  @Test(arguments: ComparisonMode.allCases)
  func lineOfSpacesThatTheModeCountsAsBlankStillCounts(mode: ComparisonMode) async throws {
    let trailing = IgnoreRule(name: "Trailing whitespace", pattern: #"[ \t]+$"#)

    let session = try await diff("a\nb\n", "a\n  \t\nb\n", mode: mode, ignoring: [trailing])

    let ignoresWhitespace = mode == .ignoreWhitespaceAmount || mode == .ignoreAllWhitespace
    #expect(session.blocks.contains { $0.kind == .changed } == ignoresWhitespace)
  }

  @Test func matchedLineAtTheStartOfAChangeLeavesIt() async throws {
    let session = try await diff("x\ny\n", "// built 2026-11-15\nx2\ny\n", ignoring: [Self.stamp])

    #expect(
      Self.blocks(of: session) == [
        "unchanged 0..<0 0..<1", "changed 0..<1 1..<2", "unchanged 1..<2 2..<3",
      ])
    #expect(IgnoredDifferences(in: session).lines(in: .b) == IndexSet(integer: 0))
  }

  @Test func matchedLineAtTheEndOfAChangeLeavesIt() async throws {
    let session = try await diff("x\ny\n", "x2\n// built 2026-11-15\ny\n", ignoring: [Self.stamp])

    #expect(
      Self.blocks(of: session) == [
        "changed 0..<1 0..<1", "unchanged 1..<1 1..<2", "unchanged 1..<2 2..<3",
      ])
    #expect(IgnoredDifferences(in: session).lines(in: .b) == IndexSet(integer: 1))
  }

  @Test func matchedLineBetweenChangesStaysInTheChangeAndShowsItsPlaces() async throws {
    let session = try await diff(
      "x\ny\n", "x2\n// built 2026-11-15\ny2\n", ignoring: [Self.stamp])

    #expect(Self.blocks(of: session) == ["changed 0..<2 0..<3"])
    let ignored = IgnoredDifferences(in: session)
    #expect(ignored.lines(in: .b).isEmpty)
    #expect(!ignored.isEmpty)
    #expect(!ignored.includesDifferencesThatRulesIgnore)
    #expect(
      try ignored.places(in: .b, of: session) == [IgnoredDifferences.Place(line: 1, range: 0..<19)])
  }

  @Test func ruleThatEmptiesBothFilesLeavesNoChange() async throws {
    let everyLine = IgnoreRule(name: "Every line", pattern: ".+")

    let session = try await diff("one\ntwo\nthree\n", "four\n", ignoring: [everyLine])

    #expect(!session.blocks.contains { $0.kind == .changed })
    #expect(session.rowLayout.lineCount(in: .a) == 3)
    let ignored = IgnoredDifferences(in: session)
    #expect(ignored.lines(in: .a) == IndexSet(0..<3))
    #expect(ignored.lines(in: .b) == IndexSet(integer: 0))
    #expect(ignored.includesDifferencesThatRulesIgnore)
  }

  @Test func lineThatDiffersOnlyInMatchedTextIsAnIgnoredDifferenceInEveryMode() async throws {
    for mode in ComparisonMode.allCases {
      let session = try await diff(
        "Grüße 😀 2026-01-01 ok\n", "Grüße 😀 2026-11-15 ok\n", mode: mode, ignoring: [Self.date])

      let ignored = IgnoredDifferences(in: session)
      #expect(ignored.lines(in: .a) == IndexSet(integer: 0), "\(mode)")
      #expect(ignored.lines(in: .b) == IndexSet(integer: 0), "\(mode)")
      #expect(ignored.includesDifferencesThatRulesIgnore, "\(mode)")
      #expect(
        try ignored.places(in: .a, of: session) == [
          IgnoredDifferences.Place(line: 0, range: 9..<19)
        ],
        "\(mode)")
    }
  }

  @Test func placesOfALineThatStandsAloneAreItsMatchedText() async throws {
    let stamp = IgnoreRule(name: "Indented build stamp", pattern: "// built .*$")
    let session = try await diff(
      "a\n", "a\n  // built 2026-11-15\r\n", mode: .ignoreWhitespaceAmount, ignoring: [stamp])

    let places = try IgnoredDifferences(in: session).places(in: .b, of: session)

    #expect(places == [IgnoredDifferences.Place(line: 1, range: 2..<21)])
  }

  @Test func placesJoinMatchedTextAndOtherWhitespace() async throws {
    let session = try await diff(
      "x 2026-01-01  y\n", "x 2026-11-15 y\n", mode: .ignoreWhitespaceAmount,
      ignoring: [Self.date])

    let places = try IgnoredDifferences(in: session).places(in: .a, of: session)

    #expect(places == [IgnoredDifferences.Place(line: 0, range: 2..<14)])
  }

  @Test func differenceThatOnlyTheModeIgnoresIsNotOneOfTheRules() async throws {
    let session = try await diff(
      "a  2026-01-01\n", "a 2026-01-01\n", mode: .ignoreWhitespaceAmount, ignoring: [Self.date])

    let ignored = IgnoredDifferences(in: session)
    #expect(ignored.lines(in: .a) == IndexSet(integer: 0))
    #expect(!ignored.includesDifferencesThatRulesIgnore)
  }

  @Test func bytewiseEqualLinesAreNoIgnoredDifferenceWithRules() async throws {
    let session = try await diff("built 2026-01-01\n", "built 2026-01-01\n", ignoring: [Self.date])

    #expect(IgnoredDifferences(in: session).isEmpty)
  }

  @Test func matchedTextIsNotHighlightedWithinAChange() async throws {
    let session = try await diff(
      "let x = 1 // 2026-01-01\n", "let y = 1 // 2026-11-15\n", ignoring: [Self.date])

    #expect(try session.highlightedTexts(of: .a, inFirst: .changed) == ["x"])
    #expect(try session.highlightedTexts(of: .b, inFirst: .changed) == ["y"])
  }

  @Test func matchedTextOnOneSideOnlyIsStillHighlighted() async throws {
    let session = try await diff(
      "let x = 1 // 2026-01-01\n", "let y = 1 // 2026-01-0X\n", ignoring: [Self.date])

    #expect(try session.highlightedTexts(of: .b, inFirst: .changed).contains("0X"))
  }

  @Test func runThatReachesPastTheMatchedTextIsHighlighted() async throws {
    let session = try await diff(
      "let value = compute(1) // 2026-01-01a\n", "let value = compute(1) // 2026-11-15b\n",
      ignoring: [Self.date])

    #expect(try session.highlightedTexts(of: .a, inFirst: .changed) == ["01a"])
    #expect(try session.highlightedTexts(of: .b, inFirst: .changed) == ["15b"])
  }

  @Test func matchedTextThatTheOtherSideLacksIsNotHighlighted() async throws {
    let session = try await diff(
      "let x = 1 @\n", "let y = 1 @2026-11-15\n", ignoring: [Self.date])

    #expect(try session.highlightedTexts(of: .b, inFirst: .changed) == ["y"])
    #expect(try session.removalMarks(of: .a, inFirst: .changed).isEmpty)
  }

  @Test func matchedLineBetweenChangesIsNotHighlightedAsAChange() async throws {
    let session = try await diff(
      "let alpha = compute(1)\nlet beta = compute(2)\n",
      "let alpha = compute(10)\n// built 2026-11-15\nlet beta = compute(20)\n",
      ignoring: [Self.stamp])

    #expect(Self.blocks(of: session) == ["changed 0..<2 0..<3"])
    let highlighted = try session.highlightedTexts(of: .b, inFirst: .changed)
    #expect(!highlighted.isEmpty)
    #expect(!highlighted.contains { $0.contains("built") })
    #expect(
      try IgnoredDifferences(in: session).places(in: .b, of: session) == [
        IgnoredDifferences.Place(line: 1, range: 0..<19)
      ])
  }

  @Test func blankLineNextToAMatchedLineIsTheOnlyChangeBetweenThem() async throws {
    let session = try await diff(
      "let alpha = compute(1)\nlet beta = compute(2)\n",
      "let alpha = compute(10)\n// built 2026-11-15\n\nlet beta = compute(20)\n",
      ignoring: [Self.stamp])

    #expect(Self.blocks(of: session) == ["changed 0..<2 0..<4"])
    let highlighted = try session.highlightedTexts(of: .b, inFirst: .changed)
    #expect(!highlighted.isEmpty)
    #expect(!highlighted.contains { $0.contains("built") })
    #expect(try session.removalMarks(of: .a, inFirst: .changed).isEmpty)
  }

  @Test(arguments: [ComparisonMode.ignoreWhitespaceAmount, .ignoreAllWhitespace])
  func indentedMatchedLineBetweenChangesIsNotHighlighted(mode: ComparisonMode) async throws {
    let stamp = IgnoreRule(name: "Build stamp", pattern: "// built .*$")
    let session = try await diff(
      "let alpha = compute(1)\nlet beta = compute(2)\n",
      "let alpha = compute(10)\n  // built 2026-11-15\nlet beta = compute(20)\n", mode: mode,
      ignoring: [stamp])

    let highlighted = try session.highlightedTexts(of: .b, inFirst: .changed)
    #expect(!highlighted.isEmpty)
    #expect(!highlighted.contains { $0.contains("built") || $0.allSatisfy(\.isWhitespace) })
    #expect(
      try IgnoredDifferences(in: session).places(in: .b, of: session) == [
        IgnoredDifferences.Place(line: 1, range: 2..<21)
      ])
  }

  @Test func changedLineEndingOfAMatchedLineAtTheEdgeCountsInExactMode() async throws {
    let old = "a\n// built 2026-01-01\nb\n"
    let new = "a\n// built 2026-11-15\r\nb\n"

    let exact = try await diff(old, new, ignoring: [Self.stamp])
    let endings = try await diff(old, new, mode: .ignoreLineEndings, ignoring: [Self.stamp])

    #expect(
      Self.blocks(of: exact) == [
        "unchanged 0..<1 0..<1", "changed 1..<2 1..<2", "unchanged 2..<3 2..<3",
      ])
    #expect(Self.blocks(of: endings) == ["unchanged 0..<3 0..<3"])
    #expect(IgnoredDifferences(in: endings).lines(in: .b) == IndexSet(integer: 1))
  }

  @Test func changedLineEndingsOfMatchedLinesWithinAChangeCountInExactMode() async throws {
    let old = "let a = 1\n// built 2026-01-01\n// built 2026-01-02\nlet b = 2\n"
    let new = "let a = 10\n// built 2026-11-15\r\n// built 2026-11-16\r\nlet b = 3\n"

    let exact = try await diff(old, new, ignoring: [Self.stamp])
    let endings = try await diff(old, new, mode: .ignoreLineEndings, ignoring: [Self.stamp])

    #expect(Self.blocks(of: exact) == ["changed 0..<4 0..<4"])
    #expect(IgnoredDifferences(in: exact).lines(in: .b).isEmpty)
    #expect(
      Self.blocks(of: endings) == [
        "changed 0..<1 0..<1", "unchanged 1..<3 1..<3", "changed 3..<4 3..<4",
      ])
    #expect(IgnoredDifferences(in: endings).lines(in: .b) == IndexSet(1..<3))
  }

  /// Four matched lines between short changes: if the matched lines still counted towards the
  /// share of changed tokens, they would make up most of the block, and nothing would be
  /// highlighted.
  @Test func severalMatchedLinesBetweenShortChangesKeepTheirHighlights() async throws {
    let session = try await diff(
      "a = 1\nb = 2\n",
      "a = 10\n" + String(repeating: "// built 2026-11-15\n", count: 4) + "b = 3\n",
      ignoring: [Self.stamp])

    #expect(Self.blocks(of: session) == ["changed 0..<2 0..<6"])
    let highlighted = try session.highlightedTexts(of: .b, inFirst: .changed)
    #expect(highlighted == ["10", "3"])
  }

  @Test func sideThatReplacedALineWithAMatchedLineMarksTheMissingText() async throws {
    let session = try await diff(
      "let a = compute(1)\nfoo bar\nlet b = 2\n",
      "let a = compute(10)\n// built 2026-11-15\nlet b = 3\n", ignoring: [Self.stamp])

    #expect(try session.highlightedTexts(of: .a, inFirst: .changed).contains { $0.contains("foo") })
    #expect(try !session.removalMarks(of: .b, inFirst: .changed).isEmpty)
    #expect(
      try !session.highlightedTexts(of: .b, inFirst: .changed).contains { $0.contains("built") })
  }

  @Test func matchedTextThatComesWithANewLineBreakIsStillHighlighted() async throws {
    let session = try await diff(
      "let value = compute(1) // 2026-01-01 done\n",
      "let value = compute(1) // 2026-11-15\n done\n", ignoring: [Self.date])

    #expect(try session.highlightedTexts(of: .b, inFirst: .changed).contains("15"))
  }

  @Test func matchedTextThatTheOtherLineLacksAfterItIsNoPlace() async throws {
    let session = try await diff(
      "x 2026-01-01\n", "x 2026-01-01 2026-02-02\n", mode: .ignoreWhitespaceAmount,
      ignoring: [Self.date])

    let ignored = IgnoredDifferences(in: session)
    #expect(try ignored.places(in: .a, of: session).isEmpty)
    #expect(
      try ignored.places(in: .b, of: session) == [IgnoredDifferences.Place(line: 0, range: 12..<23)]
    )
  }

  @Test func matchedTextThatBothLinesShareIsNoPlace() async throws {
    let session = try await diff(
      "a  2026-01-01\n", "a 2026-01-01\n", mode: .ignoreWhitespaceAmount, ignoring: [Self.date])

    let places = try IgnoredDifferences(in: session).places(in: .a, of: session)

    #expect(places == [IgnoredDifferences.Place(line: 0, range: 1..<3)])
  }

  /// The placeholder that stands for a matched line in the comparison never reaches what the
  /// panes show: neither the rows, nor the highlights within lines, nor the places of ignored
  /// differences.
  @Test(arguments: ComparisonMode.allCases)
  func placeholderOfMatchedLinesNeverReachesShownText(mode: ComparisonMode) async throws {
    let old = "a\n// built 2026-01-01\nlet x = 1 // 2026-01-01\nb\r\n// built 2026-01-02\rz"
    let new = "a\nlet y = 1 // 2026-11-15\n// built 2026-11-15\nb\r\nz"

    let session = try await diff(old, new, mode: mode, ignoring: [Self.stamp, Self.date])
    let unmasked = try await diff(old, new, mode: mode)

    let ignored = IgnoredDifferences(in: session)
    for role in [Role.a, .b] {
      let display = try session.displayString(of: role)
      #expect(!display.contains("\u{FFFD}"))
      #expect(try session.lineTexts(of: role) == unmasked.lineTexts(of: role))
      for block in session.blocks {
        for range in try session.inlineHighlights(for: block).ranges(in: role) {
          #expect(!display.utf16Substring(range).contains("\u{FFFD}"))
        }
      }
      let lines = try session.lineTexts(of: role)
      for place in try ignored.places(in: role, of: session) {
        let text = lines[place.line].utf16Substring(place.range)
        #expect(!text.isEmpty && !text.contains("\u{FFFD}"))
      }
    }
  }

  /// Random comparisons of lines among which some are build stamps: the blocks still cover both
  /// files without a gap, every change keeps lines that count, and the lines that stand alone in
  /// an unchanged block are build stamps.
  @Test func randomComparisonsWithStampsKeepTheirBlocksWithoutGaps() async throws {
    let seed: UInt64 = 2027
    var generator = SplitMix64(seed: seed)
    let pool = ["x", "y", "z", "", "  ", "// built 1", "// built 2", "  // built 3"]
    for round in 0..<300 {
      let texts = (0..<2).map { _ in
        (0..<Int.random(in: 0..<12, using: &generator)).map { _ in
          (pool.randomElement(using: &generator) ?? "") + "\n"
        }.joined()
      }
      for mode in ComparisonMode.allCases {
        let session = try await diff(texts[0], texts[1], mode: mode, ignoring: [Self.stamp])
        let context = "Seed \(seed), round \(round), \(mode): \(texts.map(\.debugDescription))"
        var next = [Role.a: 0, .b: 0]
        for block in session.blocks {
          for role in [Role.a, .b] {
            #expect(block.lines(in: role).lowerBound == next[role], "\(context)")
            next[role] = block.lines(in: role).upperBound
          }
          if block.kind == .unchanged, block.a.count != block.b.count {
            #expect(block.a.isEmpty || block.b.isEmpty, "\(context)")
            for role in [Role.a, .b] {
              let lines = try session.lineTexts(of: role)
              #expect(
                block.lines(in: role).allSatisfy { lines[$0].hasPrefix("// built") }, "\(context)")
            }
          }
        }
        for role in [Role.a, .b] {
          #expect(next[role] == session.rowLayout.lineCount(in: role), "\(context)")
        }
      }
    }
  }
}
