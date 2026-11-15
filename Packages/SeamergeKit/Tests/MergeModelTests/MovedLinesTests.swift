import MergeModel
import Testing

struct MovedLinesTests {
  static let first = "func first() {\n  let value = compute(1)\n  return value\n}\n"
  static let second = "func second() {\n  let other = compute(2)\n  return other\n}\n"
  static let third = "func third() {\n  let result = compute(3)\n  return result\n}\n"

  /// `text` with every line indented by `width` spaces.
  static func indented(_ text: String, by width: Int = 2) -> String {
    let indentation = String(repeating: " ", count: width)
    return text.split(separator: "\n").map { indentation + $0 + "\n" }.joined()
  }

  /// The moves of a comparison as the line ranges of their two ends.
  static func movedLines(of session: Session) -> [[Range<Int>]] {
    session.moves.map { [$0.source.lines, $0.destination.lines] }
  }

  @Test func functionMovedDownMovesFromItsOldPlaceToItsNewOne() async throws {
    let session = try await diff(
      Self.first + Self.second + Self.third, Self.second + Self.third + Self.first)

    #expect(Self.movedLines(of: session) == [[0..<4, 8..<12]])
    let move = try #require(session.moves.first)
    #expect(move.source.role == .a)
    #expect(move.destination.role == .b)
  }

  @Test func functionMovedUpMovesFromItsOldPlaceToItsNewOne() async throws {
    let session = try await diff(
      Self.first + Self.second + Self.third, Self.third + Self.first + Self.second)

    #expect(Self.movedLines(of: session) == [[8..<12, 0..<4]])
  }

  @Test func twoSwappedFunctionsAreOneMoveAroundTheOther() async throws {
    let session = try await diff(Self.first + Self.second, Self.second + Self.first)

    let moved = Self.movedLines(of: session)
    #expect(moved == [[0..<4, 4..<8]] || moved == [[4..<8, 0..<4]])
  }

  @Test func runAddedTwiceIsNoMove() async throws {
    let session = try await diff(
      Self.first + Self.second + Self.third, Self.second + Self.third + Self.first + Self.first)

    #expect(session.moves.isEmpty)
  }

  @Test func runRemovedTwiceIsNoMove() async throws {
    let session = try await diff(
      Self.first + Self.first + Self.second + Self.third, Self.second + Self.third + Self.first)

    #expect(session.moves.isEmpty)
  }

  @Test func runWithFewerThanTwentyLettersAndDigitsIsNoMove() async throws {
    let short = "  return value\n}\n"
    let session = try await diff(
      short + Self.second + Self.third, Self.second + Self.third + short)

    #expect(session.moves.isEmpty)
  }

  @Test func runWithTwentyLettersAndDigitsIsAMove() async throws {
    let twenty = "abcdefghij\n0123456789\n"
    let session = try await diff(
      twenty + Self.second + Self.third, Self.second + Self.third + twenty)

    #expect(Self.movedLines(of: session) == [[0..<2, 8..<10]])
  }

  @Test func reindentedFunctionMovesOnlyWhereWhitespaceAmountIsIgnored() async throws {
    let old = Self.indented(Self.first, by: 2) + Self.second + Self.third
    let new = Self.second + Self.third + Self.indented(Self.first, by: 4)

    #expect(try await diff(old, new, mode: .exact).moves.isEmpty)
    let ignoring = try await diff(old, new, mode: .ignoreWhitespaceAmount)
    #expect(Self.movedLines(of: ignoring) == [[0..<4, 8..<12]])
  }

  @Test func otherComparisonModeFindsTheMovesAnew() async throws {
    let session = try await diff(
      Self.first + Self.second + Self.third, Self.second + Self.third + Self.indented(Self.first))

    let ignoring = try await session.recomputed(
      options: ComparisonOptions(mode: .ignoreAllWhitespace))
    #expect(Self.movedLines(of: ignoring) == [[0..<4, 8..<12]])
    let exact = try await ignoring.recomputed(options: ComparisonOptions(mode: .exact))
    #expect(exact.moves.isEmpty)
  }

  @Test func moveEndsLieInTheBlocksThatHoldTheirLines() async throws {
    let session = try await diff(
      Self.first + Self.second + Self.third, Self.second + Self.third + Self.first)

    for move in session.moves {
      for end in [move.source, move.destination] {
        let block = session.blocks[end.block]
        #expect(block.kind == .changed)
        #expect(block.lines(in: end.role).clamped(to: end.lines) == end.lines)
      }
    }
  }

  /// A function whose third line the tests change.
  static let longer =
    "func longer() {\n  let value = compute(1)\n  let more = compute(11)\n  return value + more\n}\n"

  @Test(arguments: ComparisonMode.allCases)
  func movedFunctionWithAChangedLineMovesTheStretchThatStayedEqual(mode: ComparisonMode)
    async throws
  {
    let changed = Self.longer.replacingOccurrences(of: "compute(11)", with: "compute(12)")
    let session = try await diff(
      Self.longer + Self.second + Self.third, Self.second + Self.third + changed, mode: mode)

    #expect(Self.movedLines(of: session) == [[0..<2, 8..<10]])
  }

  @Test(arguments: ComparisonMode.allCases)
  func whitespaceWhereThereWasNoneSplitsAMoveUnlessAllWhitespaceIsIgnored(mode: ComparisonMode)
    async throws
  {
    let respaced = Self.longer.replacingOccurrences(of: "more = compute", with: "more=compute")
    let session = try await diff(
      Self.longer + Self.second + Self.third, Self.second + Self.third + respaced, mode: mode)

    let expected = mode == .ignoreAllWhitespace ? [[0..<5, 8..<13]] : [[0..<2, 8..<10]]
    #expect(Self.movedLines(of: session) == expected)
  }

  @Test func linesTheEngineTellsApartDespiteTheirFingerprintDoNotMove() async throws {
    // Ignoring line endings, a last line without one still differs from one that ends in CRLF.
    let withoutLastLineEnding = String(Self.first.dropLast())
    let withCRLF = Self.first.replacingOccurrences(of: "\n", with: "\r\n")
    let session = try await diff(
      Self.second + Self.third + withoutLastLineEnding, withCRLF + Self.second + Self.third,
      mode: .ignoreLineEndings)

    #expect(Self.movedLines(of: session) == [[8..<11, 0..<3]])
  }

  @Test func runsThatShareAClosingLineEachKeepTheirOwnLines() async throws {
    let first = "let firstUnique = alpha(beta)\n"
    let second = "let secondUnique = gamma(delta)\n"
    let session = try await diff(
      first + "}\n" + "let removed = gone\n" + "}\n" + second + Self.second + Self.third,
      Self.second + Self.third + first + "}\n" + second)

    #expect(Self.movedLines(of: session) == [[0..<2, 8..<10], [4..<5, 10..<11]])
    var next = 0
    for block in session.blocks {
      #expect(block.b.lowerBound == next)
      next = block.b.upperBound
    }
    #expect(next == 11)
  }

  @Test func uniqueLastLineTheEngineTellsApartFromItsCRLFTwinDoesNotMove() async throws {
    let line = "let finalUniqueLine = compute(99)"
    let session = try await diff(
      Self.second + Self.third + line, line + "\r\n" + Self.second + Self.third,
      mode: .ignoreLineEndings)

    #expect(session.moves.isEmpty)
  }

  @Test(arguments: ComparisonMode.allCases)
  func lineThatDiffersOnlyInMissingWhitespaceLeavesAMoveUniqueUnlessAllIsIgnored(
    mode: ComparisonMode
  ) async throws {
    let line = "let alpha = compute(1234567890)\n"
    let unspaced = "let alpha=compute(1234567890)\n"
    let session = try await diff(
      line + Self.second + Self.third, Self.second + Self.third + line + unspaced, mode: mode)

    let expected = mode == .ignoreAllWhitespace ? [] : [[0..<1, 8..<9]]
    #expect(Self.movedLines(of: session) == expected)
  }

  @Test func stretchThatStayedEqualWithoutAUniqueLineDoesNotMove() async throws {
    // The anchor, the last line, differs from its twin as the engine sees it; the lines before
    // it stay equal but are added twice.
    let shared = "let shared = compute(42)\nlet other = compute(43)\n"
    let anchor = "let anchor = compute(44)"
    let session = try await diff(
      Self.second + Self.third + shared + anchor,
      shared + anchor + "\r\n" + shared + Self.second + Self.third, mode: .ignoreLineEndings)

    #expect(session.moves.isEmpty)
  }
}
