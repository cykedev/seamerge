import Foundation
import MergeEngine
import MergeModel
import Testing

struct MoveSplitTests {
  static let first = MovedLinesTests.first
  static let second = MovedLinesTests.second
  static let third = MovedLinesTests.third
  static let fourth = "func fourth() {\n  let last = compute(4)\n  return last\n}\n"

  @Test func runInALargerChangedBlockBecomesABlockOfItsOwnBetweenChanges() async throws {
    let session = try await diff(
      Self.second + "let before = 1\n" + Self.first + "let after = 1\n" + Self.third + Self.fourth,
      Self.second + "let before = 2\n" + "let after = 2\n" + Self.third + Self.fourth + Self.first)

    #expect(
      session.blocks.map(\.kind) == [
        .unchanged, .changed, .changed, .changed, .unchanged, .changed,
      ])
    #expect(session.blocks.map(\.a) == [0..<4, 4..<5, 5..<9, 9..<10, 10..<18, 18..<18])
    #expect(session.blocks.map(\.b) == [0..<4, 4..<5, 5..<5, 5..<6, 6..<14, 14..<18])
    #expect(session.moves.count == 1)
    let move = try #require(session.moves.first)
    #expect(move.source.block == 2 && move.destination.block == 5)
    #expect([move.source.role, move.destination.role] == [.a, .b])
    #expect([move.source.lines, move.destination.lines] == [5..<9, 14..<18])
  }

  @Test func eachEndOfAMoveIsABlockWithLinesOnlyInItsInput() async throws {
    let session = try await diff(
      Self.first + Self.second + Self.third, Self.third + Self.first + Self.second)

    let move = try #require(session.moves.first)
    for end in [move.source, move.destination] {
      let block = session.blocks[end.block]
      #expect(block.kind == .changed)
      #expect(block.lines(in: end.role) == end.lines)
      #expect(block.lines(in: end.role == .a ? .b : .a).isEmpty)
    }
  }

  @Test func eachEndFindsItsMoveOnlyOnThePaneOfItsInput() async throws {
    let session = try await diff(
      Self.first + Self.second + Self.third, Self.second + Self.third + Self.first)

    let move = try #require(session.moves.first)
    let source = session.blocks[move.source.block]
    let destination = session.blocks[move.destination.block]
    #expect(session.move(endingIn: source, on: .a) == move)
    #expect(session.move(endingIn: destination, on: .b) == move)
    #expect(session.move(endingIn: source, on: .b) == nil)
    #expect(session.move(endingIn: destination, on: .a) == nil)
    for block in session.blocks where block.id != source.id && block.id != destination.id {
      #expect(session.move(endingIn: block, on: .a) == nil)
      #expect(session.move(endingIn: block, on: .b) == nil)
    }
  }

  @Test func readingFromBAsAfterSwapSidesReversesTheMove() async throws {
    let session = try await diff(
      Self.first + Self.second + Self.third, Self.second + Self.third + Self.first)

    let move = try #require(session.moves.first)
    let source = session.blocks[move.source.block]
    let read = try #require(session.move(endingIn: source, on: .a, readingFrom: .b))
    #expect(read.source == move.destination)
    #expect(read.destination == move.source)
    #expect(session.move(endingIn: source, on: .a, readingFrom: .a) == move)
  }

  @Test func randomComparisonsKeepTheirBlocksWithoutGapsAfterTheSplit() async throws {
    let seed: UInt64 = 24
    var generator = SplitMix64(seed: seed)
    var moveCount = 0
    for run in 0..<400 {
      let input = RandomMoveInput(using: &generator)
      let mode = ComparisonMode.allCases.randomElement(using: &generator) ?? .exact
      let context = Comment(rawValue: "seed \(seed), run \(run), \(mode), \(input)")
      let session = try await diff(input.old, input.new, mode: mode)
      moveCount += session.moves.count

      #expect(session.blocks.map(\.id) == Array(session.blocks.indices), context)
      for role in session.roles {
        var next = 0
        for block in session.blocks {
          #expect(block.lines(in: role).lowerBound == next, context)
          next = block.lines(in: role).upperBound
        }
        #expect(next == session.rowLayout.lineCount(in: role), context)
      }
      #expect(!session.blocks.contains { $0.a.isEmpty && $0.b.isEmpty }, context)
      let engineBlocks = try Self.engineBlocks(of: input, in: mode)
      #expect(Self.joined(session.blocks) == engineBlocks, context)
      for move in session.moves {
        #expect(session.blocks[move.source.block].a == move.source.lines, context)
        #expect(session.blocks[move.source.block].b.isEmpty, context)
        #expect(session.blocks[move.destination.block].b == move.destination.lines, context)
        #expect(session.blocks[move.destination.block].a.isEmpty, context)
      }
    }
    #expect(moveCount > 50, "seed \(seed), \(moveCount) moves")
  }

  /// The blocks with each run of changed blocks joined into one, as kinds and line ranges.
  static func joined(_ blocks: [Block]) -> [BlockSpan] {
    var spans: [BlockSpan] = []
    for block in blocks {
      let span = BlockSpan(isChanged: block.kind == .changed, a: block.a, b: block.b)
      if let last = spans.last, last.isChanged, span.isChanged {
        spans[spans.count - 1] = BlockSpan(
          isChanged: true, a: last.a.lowerBound..<span.a.upperBound,
          b: last.b.lowerBound..<span.b.upperBound)
      } else {
        spans.append(span)
      }
    }
    return spans
  }

  /// The blocks of the engine's comparison of the input, as kinds and line ranges.
  static func engineBlocks(of input: RandomMoveInput, in mode: ComparisonMode) throws -> [BlockSpan]
  {
    let whitespace: Whitespace =
      switch mode {
      case .exact: .exact
      case .ignoreLineEndings: .ignoreLineEndings
      case .ignoreWhitespaceAmount: .ignoreAmount
      case .ignoreAllWhitespace: .ignoreAll
      }
    let engine = try MergeEngine.Diff(
      Data(input.old.utf8), Data(input.new.utf8), whitespace: whitespace)
    return engine.blocks.map {
      BlockSpan(isChanged: $0.kind == .changed, a: $0.a.lines, b: $0.b.lines)
    }
  }

  /// Whether a block changed, and its lines in A and in B.
  struct BlockSpan: Hashable {
    var isChanged: Bool
    var a: Range<Int>
    var b: Range<Int>
  }
}

/// Two files of code-like lines where the newer one moves runs of lines of the older one, and
/// changes, removes, inserts and re-indents others.
struct RandomMoveInput: CustomStringConvertible {
  let old: String
  let new: String

  static let vocabulary = [
    "func alpha() {", "  let value = compute(1)", "  return value", "}", "", "  return",
    "let beta = gamma(2) + delta", "// A comment that explains the code", "case .first: one",
    "  if condition { proceed() }", "struct Container {",
  ]

  init(using generator: inout SplitMix64) {
    var lines = (0..<Int.random(in: 0...30, using: &generator)).map { _ in
      Self.vocabulary.randomElement(using: &generator) ?? ""
    }
    // Unique lines make moves likely to be found, the vocabulary makes repeated lines likely.
    for index in lines.indices where Int.random(in: 0..<3, using: &generator) == 0 {
      lines[index] += " \(Int.random(in: 0...999, using: &generator))"
    }
    old = Self.text(of: lines, using: &generator)
    var edited = lines
    for _ in 0..<Int.random(in: 0...4, using: &generator) {
      guard !edited.isEmpty else { break }
      let start = Int.random(in: 0..<edited.count, using: &generator)
      let end = Int.random(in: start...min(edited.count, start + 6), using: &generator)
      switch Int.random(in: 0...5, using: &generator) {
      case 0, 1, 2:
        let run = edited[start..<end]
        edited.removeSubrange(start..<end)
        edited.insert(contentsOf: run, at: Int.random(in: 0...edited.count, using: &generator))
      case 3:
        edited[start] = "let changed = \(Int.random(in: 0...9, using: &generator))"
      case 4:
        edited.removeSubrange(start..<end)
      default:
        for index in start..<end { edited[index] = "  " + edited[index] }
      }
    }
    new = Self.text(of: edited, using: &generator)
  }

  var description: String { "old: \(old.debugDescription) new: \(new.debugDescription)" }

  /// The lines joined with LF or, now and then, CRLF, and without a final line ending now and
  /// then.
  private static func text(of lines: [String], using generator: inout SplitMix64) -> String {
    let lineEnding = Int.random(in: 0..<5, using: &generator) == 0 ? "\r\n" : "\n"
    var text = lines.map { $0 + lineEnding }.joined()
    if Int.random(in: 0..<4, using: &generator) == 0 {
      text = String(text.dropLast(lineEnding.count))
    }
    return text
  }
}
