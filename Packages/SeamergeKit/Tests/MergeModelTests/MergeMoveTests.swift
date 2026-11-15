import Foundation
import MergeEngine
import MergeModel
import Testing

struct MergeMoveTests {
  static let first = MovedLinesTests.first
  static let second = MovedLinesTests.second
  static let third = MovedLinesTests.third
  static let base = first + second + third
  static let moved = second + third + first

  /// A function named `name` with enough letters to move.
  static func function(_ name: String) -> String {
    "func \(name)() {\n  let value = compute(\"\(name)\")\n  return value\n}\n"
  }

  @Test func functionThatAMovedIsAMoveBetweenTwoWholeBlocksInItsPane() async throws {
    let input = RandomMergeInput(base: Self.base, a: Self.moved, b: Self.base)
    let session = try await input.session(mode: .exact, strategy: .optimal)

    try Self.expectBlocksOfTheEngine(in: session, for: input)
    let move = try #require(session.moves.first)
    #expect(session.moves.count == 1)
    let source = session.blocks[move.source.block]
    let destination = session.blocks[move.destination.block]
    #expect(move.source.role == .a && move.destination.role == .a)
    #expect([source.kind, destination.kind] == [.changedInA, .changedInA])
    #expect(source.base == 0..<4 && source.a.isEmpty && move.source.lines == source.a)
    #expect(destination.base.isEmpty && destination.a == 8..<12)
    #expect(move.destination.lines == 8..<12)
    #expect(session.move(endingIn: source, on: .a) == move)
    #expect(session.move(endingIn: destination, on: .a) == move)
    #expect(session.move(endingIn: source, on: .b) == nil)
    #expect(session.move(endingIn: source, on: .base) == nil)
  }

  @Test func functionThatBMovedIsAMoveInThePaneOfB() async throws {
    let input = RandomMergeInput(base: Self.base, a: Self.base, b: Self.moved)
    let session = try await input.session(mode: .exact, strategy: .optimal)

    try Self.expectBlocksOfTheEngine(in: session, for: input)
    let move = try #require(session.moves.first)
    #expect(session.moves.count == 1)
    #expect(move.source.role == .b && move.destination.role == .b)
    #expect(session.blocks[move.source.block].kind == .changedInB)
    #expect(move.destination.lines == 8..<12)
  }

  @Test func moveOfAExplainsAConflictWithAChangeOfBAtTheOldPlace() async throws {
    let changed = Self.first.replacingOccurrences(of: "compute(1)", with: "compute(10)")
    let input = RandomMergeInput(
      base: Self.base, a: Self.moved, b: changed + Self.second + Self.third)
    let session = try await input.session(mode: .exact, strategy: .optimal)

    try Self.expectBlocksOfTheEngine(in: session, for: input)
    let move = try #require(session.moves.first)
    #expect(session.moves.count == 1)
    #expect(move.source.role == .a)
    #expect(session.blocks[move.source.block].kind == .conflict)
    #expect(session.blocks[move.destination.block].kind == .changedInA)
  }

  @Test func bothSidesMovingTheSameFunctionAreAMoveInEachPane() async throws {
    let input = RandomMergeInput(base: Self.base, a: Self.moved, b: Self.moved)
    let session = try await input.session(mode: .exact, strategy: .optimal)

    #expect(session.moves.map(\.source.role) == [.a, .b])
    #expect(Set(session.moves.map(\.source.block)).count == 1)
  }

  @Test func addedLinesThatAreMoreThanTheRemovedOnesAreNoMove() async throws {
    let extra = "let extra = compute(5)\n"
    let input = RandomMergeInput(
      base: Self.base, a: Self.second + Self.third + Self.first + extra, b: Self.base)
    let session = try await input.session(mode: .exact, strategy: .optimal)

    #expect(session.moves.isEmpty)
  }

  @Test func removalThatRecursTwiceIsNoMove() async throws {
    let (x, y, z) = (Self.function("x"), Self.function("y"), Self.function("z"))
    let input = RandomMergeInput(
      base: Self.first + Self.second + x + y + Self.first + Self.third + z,
      a: Self.second + x + y + Self.third + z + Self.first,
      b: Self.first + Self.second + x + y + Self.first + Self.third + z)
    let session = try await input.session(mode: .exact, strategy: .optimal)

    try #require(session.blocks.map(\.base).filter { $0.count == 4 } == [0..<4, 16..<20])
    #expect(!session.moves.contains { $0.source.role == .a })
  }

  @Test func additionThatRecursTwiceIsNoMove() async throws {
    let (x, y) = (Self.function("x"), Self.function("y"))
    let base = Self.first + Self.second + x + Self.third + y
    let input = RandomMergeInput(
      base: base, a: Self.second + x + Self.first + Self.third + y + Self.first, b: base)
    let session = try await input.session(mode: .exact, strategy: .optimal)

    try #require(session.blocks.count { $0.base.isEmpty && $0.a.count == 4 } == 2)
    #expect(session.moves.isEmpty)
  }

  @Test func contributionsTheEngineTellsApartDespiteTheirFingerprintDoNotMove() async throws {
    // Ignoring line endings, a last line without one still differs from one that ends in CRLF.
    let base = Self.second + Self.third + String(Self.first.dropLast())
    let a = Self.first.replacingOccurrences(of: "\n", with: "\r\n") + Self.second + Self.third
    let session = try await merge(base: base, a: a, b: base, mode: .ignoreLineEndings)

    try #require(session.blocks.count { $0.kind == .changedInA } == 2)
    #expect(session.moves.isEmpty)
  }

  @Test func mergeWithoutABaseHasNoMoves() async throws {
    let session = try await merge(base: nil, a: Self.base, b: Self.moved)

    #expect(session.moves.isEmpty)
  }

  @Test func reindentedMoveCountsWhereWhitespaceAmountIsIgnored() async throws {
    let base = MovedLinesTests.indented(Self.first) + Self.second + Self.third
    let a = Self.second + Self.third + MovedLinesTests.indented(Self.first, by: 4)

    #expect(try await merge(base: base, a: a, b: base).moves.isEmpty)
    let session = try await merge(base: base, a: a, b: base, mode: .ignoreWhitespaceAmount)
    #expect(session.moves.count == 1)
  }

  @Test(arguments: MergeModel.MergeStrategy.allCases)
  func resultOfAMergeWithMovesHasTheBytesOfTheEngine(strategy: MergeModel.MergeStrategy)
    async throws
  {
    let changed = Self.first.replacingOccurrences(of: "compute(1)", with: "compute(10)")
    let changedThird = Self.third.replacingOccurrences(of: "compute(3)", with: "compute(30)")
    let inputs = [
      RandomMergeInput(base: Self.base, a: Self.moved, b: changed + Self.second + Self.third),
      RandomMergeInput(base: Self.base, a: Self.moved, b: Self.moved),
      RandomMergeInput(base: Self.base, a: Self.moved, b: Self.first + Self.second + changedThird),
      RandomMergeInput(base: Self.base, a: Self.base, b: Self.moved),
    ]
    for input in inputs {
      let session = try await input.session(mode: .exact, strategy: strategy)
      try #require(!session.moves.isEmpty, "\(input)")
      try Self.expectBlocksOfTheEngine(in: session, for: input, strategy: strategy)
      var buffer = ResultBuffer(session)
      var resolutions: [Int: Merge.Source] = [:]
      for block in session.blocks where block.kind == .conflict {
        resolutions[block.id] = .a
        buffer.perform(buffer.document.planChoosing([.a], in: block))
      }
      let engine = try input.engineMerge(mode: .exact, strategy: strategy)
      let output = try #require(engine.result(resolutions: resolutions))
      #expect(Data(buffer.text.utf8) == output.data, "\(input)")
    }
  }

  /// Expects the blocks of `session` to be those of the engine's merge of `input`: none split.
  static func expectBlocksOfTheEngine(
    in session: Session, for input: RandomMergeInput,
    strategy: MergeModel.MergeStrategy = .optimal
  ) throws {
    let engine = try input.engineMerge(mode: session.options.mode, strategy: strategy)
    #expect(session.blocks.map(\.base) == engine.blocks.map(\.base.lines))
    #expect(session.blocks.map(\.a) == engine.blocks.map(\.a.lines))
    #expect(session.blocks.map(\.b) == engine.blocks.map(\.b.lines))
  }
}
