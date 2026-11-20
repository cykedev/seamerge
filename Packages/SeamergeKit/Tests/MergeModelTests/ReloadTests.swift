import Foundation
import MergeModel
import Testing

struct ReloadTests {
  /// Inputs of seven blocks: unchanged, changed in A, unchanged, a conflict, unchanged, changed
  /// in B, unchanged.
  static let base = "u0\nx1\nu2\nx3\nu4\nx5\nu6\n"
  static let a = "u0\nA1\nu2\nA3\nu4\nx5\nu6\n"
  static let b = "u0\nx1\nu2\nB3\nu4\nB5\nu6\n"

  /// A buffer of the merge of `base`, `a` and `b` with B taken for the conflict and the base
  /// for the change of A.
  private func decided() async throws -> ResultBuffer {
    var buffer = ResultBuffer(try await merge(base: Self.base, a: Self.a, b: Self.b))
    try #require(
      buffer.blocks.map(\.kind) == [
        .unchanged, .changedInA, .unchanged, .conflict, .unchanged, .changedInB, .unchanged,
      ])
    buffer.perform(buffer.document.planChoosing([.base], in: buffer.blocks[1]))
    buffer.perform(buffer.document.planChoosing([.b], in: buffer.blocks[3]))
    return buffer
  }

  @Test func reloadingTheSameFilesKeepsEveryDecision() async throws {
    var buffer = try await decided()
    let texts = buffer.segmentTexts
    let states = buffer.document.segments.map(\.state)

    let reload = buffer.document.planReloading(
      to: try await merge(base: Self.base, a: Self.a, b: Self.b), text: buffer.text)
    buffer.perform(reload.plan)

    #expect(reload.discardedDecisionCount == 0)
    #expect(buffer.segmentTexts == texts)
    #expect(buffer.document.segments.map(\.state) == states)
    buffer.checkInvariants()
  }

  @Test func linesAddedAboveABlockLetItKeepItsDecision() async throws {
    var buffer = try await decided()

    let reload = buffer.document.planReloading(
      to: try await merge(base: Self.base, a: "new\n" + Self.a, b: Self.b), text: buffer.text)
    buffer.perform(reload.plan)

    #expect(reload.discardedDecisionCount == 0)
    let conflict = try #require(buffer.blocks.first { $0.kind == .conflict })
    #expect(buffer.text(of: conflict) == "B3\n")
    #expect(buffer.document.segment(for: conflict).state == .chosen)
    buffer.checkInvariants()
  }

  @Test func blockChangedInAnInputLosesItsDecisionAndIsCounted() async throws {
    var buffer = try await decided()
    let changedA = Self.a.replacingOccurrences(of: "A3", with: "A3 changed")

    let reload = buffer.document.planReloading(
      to: try await merge(base: Self.base, a: changedA, b: Self.b), text: buffer.text)
    buffer.perform(reload.plan)

    #expect(reload.discardedDecisionCount == 1)
    let conflict = try #require(buffer.blocks.first { $0.kind == .conflict })
    #expect(buffer.document.segment(for: conflict).state == .open)
    #expect(buffer.text(of: buffer.blocks[1]) == "x1\n")
    buffer.checkInvariants()
  }

  @Test func handwrittenTextMovesOnlyWithItsBlock() async throws {
    var buffer = try await decided()
    buffer.type("hand ", at: buffer.document.range(of: buffer.blocks[5]).lowerBound)

    let moved = buffer.document.planReloading(
      to: try await merge(base: "new\n" + Self.base, a: "new\n" + Self.a, b: "new\n" + Self.b),
      text: buffer.text)
    let lost = buffer.document.planReloading(
      to: try await merge(
        base: Self.base, a: Self.a.replacingOccurrences(of: "x5", with: "A5"), b: Self.b),
      text: buffer.text)
    buffer.perform(moved.plan)

    #expect(moved.discardedDecisionCount == 0)
    #expect(buffer.segmentTexts.contains("hand B5\n"))
    #expect(lost.discardedDecisionCount == 1)
  }

  @Test func equalBlocksKeepTheirDecisionsAtTheirOwnPlaces() async throws {
    // The same conflict twice; lines added above, between and below shift both.
    let base = "u0\nx\nu1\nu2\nx\nu3\n"
    let a = "u0\nA\nu1\nu2\nA\nu3\n"
    let b = "u0\nB\nu1\nu2\nB\nu3\n"
    var buffer = ResultBuffer(try await merge(base: base, a: a, b: b))
    try #require(buffer.blocks.filter { $0.kind == .conflict }.count == 2)
    buffer.perform(buffer.document.planChoosing([.a], in: buffer.blocks[1]))
    buffer.perform(buffer.document.planChoosing([.b], in: buffer.blocks[3]))
    try #require(buffer.blocks[3].kind == .conflict)

    let shifted = buffer.document.planReloading(
      to: try await merge(base: base, a: "top\nu0\nA\nu1\nmiddle\nu2\nA\nu3\nend\n", b: b),
      text: buffer.text)
    buffer.perform(shifted.plan)

    #expect(shifted.discardedDecisionCount == 0)
    let conflicts = buffer.blocks.filter { $0.kind == .conflict }
    #expect(conflicts.map(buffer.text(of:)) == ["A\n", "B\n"])
  }

  @Test func changeMovedToEqualLinesElsewhereLosesTheDecisionInsteadOfTakingItAlong()
    async throws
  {
    // A changes the first of two equal lines, and the decision takes the base; then A moves its
    // change to the second line. The block there has the same text, but it is another block.
    let base = "s\nu1\ns\nu2\n"
    var buffer = ResultBuffer(try await merge(base: base, a: "sA\nu1\ns\nu2\n", b: base))
    try #require(buffer.blocks[0].kind == .changedInA)
    buffer.perform(buffer.document.planChoosing([.base], in: buffer.blocks[0]))

    let reload = buffer.document.planReloading(
      to: try await merge(base: base, a: "s\nu1\nsA\nu2\n", b: base), text: buffer.text)
    buffer.perform(reload.plan)

    #expect(reload.discardedDecisionCount == 1)
    #expect(buffer.text == "s\nu1\nsA\nu2\n")
    buffer.checkInvariants()
  }

  @Test func reloadingIsOneUndoStepThatBringsBackTheOldSession() async throws {
    var buffer = try await decided()
    let text = buffer.text
    let segments = buffer.document.segments

    let reload = buffer.document.planReloading(
      to: try await merge(base: Self.base, a: Self.a + "end\n", b: Self.b), text: buffer.text)
    buffer.perform(reload.plan)
    buffer.undo()

    #expect(buffer.text == text)
    #expect(buffer.document.segments == segments)
    #expect(buffer.document.session.inputs.a.text == Self.a)
  }

  /// A decision lands only where its block went, in random merges.
  ///
  /// The merges have equal lines in several places and are decided at random; then inputs gain
  /// or lose lines, or a side moves one of its changes to equal lines elsewhere. Every line carries
  /// an identity that the files do not show, which says independently of the rule where each
  /// block went: a decision may land only there.
  @Test func decisionLandsOnlyWhereItsBlockWent() async throws {
    let seed: UInt64 = 1713
    var generator = SplitMix64(seed: seed)
    var carriedCount = 0
    var discardedCount = 0
    var movedCount = 0
    for round in 0..<400 {
      let context = Comment(rawValue: "seed \(seed), round \(round)")
      var lines = TrackedLines(using: &generator)
      var buffer = ResultBuffer(try await lines.merge())
      for block in buffer.blocks where block.kind != .unchanged && Bool.random(using: &generator) {
        let choices: [[Role]] =
          block.kind == .conflict ? [[.a], [.b], [.a, .b], [.b, .a]] : [[.base]]
        let roles = choices.randomElement(using: &generator) ?? [.base]
        buffer.perform(buffer.document.planChoosing(roles, in: buffer.blocks[block.id]))
      }
      let old = buffer.document
      let before = lines
      for _ in 0..<Int.random(in: 1...3, using: &generator) {
        if lines.edit(using: &generator) {
          movedCount += 1
        }
      }
      let reloaded = try await lines.merge()
      let reload = old.planReloading(to: reloaded, text: buffer.text)
      buffer.perform(reload.plan)

      let decided = old.session.blocks.filter { old.differs($0) }
      let carried = buffer.blocks.filter { buffer.document.differs($0) }
      #expect(decided.count - carried.count == reload.discardedDecisionCount, context)
      carriedCount += carried.count
      discardedCount += reload.discardedDecisionCount
      for block in carried {
        let sources = buffer.document.segment(for: block).sources
        let origin = decided.first { origin in
          old.segment(for: origin).sources == sources
            && before.place(of: origin, in: lines) == Role.allCases.map(block.lines(in:))
        }
        #expect(origin != nil, "block \(block.id) got a decision from elsewhere, \(context)")
      }
      buffer.checkInvariants()
    }
    // Every way occurs often enough to tell something.
    #expect(
      carriedCount > 300 && discardedCount > 50 && movedCount > 50,
      "\(carriedCount), \(discardedCount), \(movedCount)")
  }
}

extension ResultDocument {
  /// Whether `block` has another decision than it was loaded with.
  fileprivate func differs(_ block: Block) -> Bool {
    let loaded = ResultDocument(session: session).segment(for: block)
    let segment = segment(for: block)
    return segment.state != loaded.state || segment.sources != loaded.sources
  }
}

/// The lines of base, A and B, each with an identity that its text does not show: the same line
/// keeps it wherever it moves, an added or rewritten line gets a new one.
private struct TrackedLines {
  struct Line: Equatable {
    var text: String
    let identity: Int
  }

  private(set) var lines: [Role: [Line]]
  private var nextIdentity = 0

  /// Unique lines with an equal line "s" between every few of them; A and B change some lines.
  init(using generator: inout SplitMix64) {
    lines = [:]
    var base: [Line] = []
    for index in 0..<Int.random(in: 6...14, using: &generator) {
      base.append(makeLine(index.isMultiple(of: 3) ? "s" : "u\(index)"))
    }
    lines[.base] = base
    for (role, suffix) in [(Role.a, "A"), (.b, "B")] {
      lines[role] = base.map { line in
        Int.random(in: 0..<4, using: &generator) == 0 ? makeLine(line.text + suffix) : line
      }
    }
  }

  private mutating func makeLine(_ text: String) -> Line {
    nextIdentity += 1
    return Line(text: text, identity: nextIdentity)
  }

  func merge() async throws -> Session {
    func text(_ role: Role) -> String {
      lines[role, default: []].map { $0.text + "\n" }.joined()
    }
    return try await MergeModelTests.merge(base: text(.base), a: text(.a), b: text(.b))
  }

  /// Adds or removes a line of one input, or moves a change of A or B to an equal line
  /// elsewhere; tells whether it moved a change.
  mutating func edit(using generator: inout SplitMix64) -> Bool {
    let role = Role.allCases.randomElement(using: &generator) ?? .a
    var input = lines[role, default: []]
    switch Int.random(in: 0..<3, using: &generator) {
    case 0:
      input.insert(
        makeLine("n\(nextIdentity)"), at: Int.random(in: 0...input.count, using: &generator))
      lines[role] = input
      return false
    case 1 where !input.isEmpty:
      input.remove(at: Int.random(in: 0..<input.count, using: &generator))
      lines[role] = input
      return false
    default:
      guard role != .base else { return false }
      let suffix = role == .a ? "A" : "B"
      let changed = input.indices.filter { input[$0].text == "s" + suffix }
      let equal = input.indices.filter { input[$0].text == "s" }
      guard let from = changed.randomElement(using: &generator),
        let to = equal.randomElement(using: &generator)
      else { return false }
      input[from] = makeLine("s")
      input[to] = makeLine("s" + suffix)
      lines[role] = input
      return true
    }
  }

  /// Where `block` of the session of these lines is in the session of `after`: the lines with
  /// the same identities in every input, or the place between the same neighbors for an empty
  /// range; `nil` where a line is gone or the neighbors no longer meet.
  func place(of block: Block, in after: TrackedLines) -> [Range<Int>]? {
    var place: [Range<Int>] = []
    for role in Role.allCases {
      let old = lines[role, default: []]
      let new = after.lines[role, default: []]
      let range = block.lines(in: role)
      let index = { (line: Line) in new.firstIndex { $0.identity == line.identity } }
      if range.isEmpty {
        let previous = range.lowerBound > 0 ? index(old[range.lowerBound - 1]).map { $0 + 1 } : 0
        let next = range.lowerBound < old.count ? index(old[range.lowerBound]) : new.count
        guard let previous, previous == next else { return nil }
        place.append(previous..<previous)
      } else {
        let indices = range.map { index(old[$0]) }
        guard let first = indices.first ?? nil,
          indices.enumerated().allSatisfy({ $0.element == first + $0.offset })
        else { return nil }
        place.append(first..<(first + range.count))
      }
    }
    return place
  }
}
