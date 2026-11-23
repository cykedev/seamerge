import MergeModel
import Testing

/// Random sequences of decisions, typing, resets and undo, between which the work is captured
/// and restored into the same merge opened anew, in the same comparison or in another one.
struct MergeWorkFuzzTests {
  /// One action on a result.
  enum Action: CustomStringConvertible {
    case type(String, Range<Int>)
    case moveCursor
    case toggle(Role, block: Int)
    case choose([Role], block: Int)
    case resolveByHand(block: Int)
    case reset(block: Int)
    case resetAll
    case undo
    case restore(inOtherComparison: Bool, currentBlock: Int)

    var description: String {
      switch self {
      case .type(let text, let range): "type \(text.debugDescription) over \(range)"
      case .moveCursor: "move cursor"
      case .toggle(let role, let block): "toggle \(role) in \(block)"
      case .choose(let roles, let block): "choose \(roles) in \(block)"
      case .resolveByHand(let block): "resolve \(block) by hand"
      case .reset(let block): "reset \(block)"
      case .resetAll: "reset all"
      case .undo: "undo"
      case .restore(let other, let current):
        "restore \(other ? "into another comparison" : "into the same blocks") at \(current)"
      }
    }
  }

  /// What a restoration of the work led to.
  enum Outcome: Hashable {
    case nothingToKeep
    case sameBlocks
    case movedCompletely
    case movedPartly
  }

  /// The comparisons of one merge: two with different options, each opened twice, so that
  /// restoring goes into a session other than the one the work was captured in.
  struct Comparisons {
    let first: [Session]
    let second: [Session]

    /// The sessions of the comparison of `session`, or of the other comparison.
    func sessions(like session: Session, other: Bool) -> [Session] {
      (session.options == first[0].options) != other ? first : second
    }
  }

  @Test func randomSequencesRestoreTheWorkAndKeepTheInvariants() async throws {
    let seed: UInt64 = 55
    var generator = SplitMix64(seed: seed)
    var pool: [Comparisons] = []
    for _ in 0..<100 {
      let input = RandomMergeInput(using: &generator)
      let modes = ComparisonMode.allCases.shuffled(using: &generator)
      pool.append(
        Comparisons(
          first: [
            try await input.session(mode: modes[0], strategy: .optimal),
            try await input.session(mode: modes[0], strategy: .optimal),
          ],
          second: [
            try await input.session(mode: modes[1], strategy: .guarded),
            try await input.session(mode: modes[1], strategy: .guarded),
          ]))
    }

    var outcomes: [Outcome: Int] = [:]
    for sequence in 0..<1_000 {
      let comparisons = pool[sequence % pool.count]
      var buffer = ResultBuffer(comparisons.first[0])
      var actions: [Action] = []
      for _ in 0..<12 {
        let action = Self.randomAction(for: buffer, using: &generator)
        actions.append(action)
        let context = Comment(rawValue: "seed \(seed), sequence \(sequence), \(actions)")
        if case .restore(let other, let current) = action {
          let target = comparisons.sessions(like: buffer.document.session, other: other)
          guard
            let (restored, outcome) = try Self.restore(
              buffer, currentBlock: current, into: target[1], context)
          else { return }
          outcomes[outcome, default: 0] += 1
          buffer = restored
        } else {
          buffer.carryOut(action)
        }
        guard buffer.checkInvariants(context) else { return }
      }
    }
    // The sequences reach every way a restoration can go.
    #expect(outcomes.count == 4, "\(outcomes)")
  }

  /// Captures the work in `buffer` and restores it into `session`, a fresh comparison of the same
  /// files, and checks the outcome; returns the buffer with the work restored, the same buffer if
  /// there was nothing to keep, or `nil` after a failed check.
  private static func restore(
    _ buffer: ResultBuffer, currentBlock: Int, into session: Session, _ context: Comment
  ) throws -> (ResultBuffer, Outcome)? {
    let current = buffer.blocks.indices.contains(currentBlock) ? buffer.blocks[currentBlock] : nil
    guard let work = try buffer.capturedWork(currentBlock: current) else {
      #expect(!buffer.document.canResetAll, context)
      return (buffer, .nothingToKeep)
    }
    var (restored, restoration) = try ResultBuffer.restoring(work, into: session)
    guard restored.checkInvariants(context) else { return nil }

    // The inputs end lines only in LF or CRLF, which every mode splits alike, so blocks with the
    // same lines cover the same bytes.
    let outcome: Outcome
    if session.blocks == buffer.document.session.blocks {
      outcome = .sameBlocks
      #expect(restoration.restartedBlockCount == 0, context)
      #expect(restored.text == buffer.text, context)
      #expect(restored.document.segments == buffer.document.segments, context)
      #expect(restoration.currentBlock?.id == current?.id, context)
      if session.options == buffer.document.session.options {
        #expect(try restored.capturedWork(currentBlock: restoration.currentBlock) == work, context)
      }
    } else {
      var switched = buffer
      let modeSwitch = buffer.document.planSwitching(to: session, text: buffer.text)
      switched.perform(modeSwitch.plan)
      outcome = restoration.restartedBlockCount == 0 ? .movedCompletely : .movedPartly
      #expect(restoration.restartedBlockCount == modeSwitch.discardedDecisionCount, context)
      #expect(restored.text == switched.text, context)
      #expect(restored.document.segments == switched.document.segments, context)
    }

    let result = restored
    restored.undo()
    #expect(restored.text == ResultDocument(session: session).initialText, context)
    #expect(!restored.document.canResetAll, context)
    return (result, outcome)
  }

  /// An action that suits the state of `buffer`.
  private static func randomAction(
    for buffer: ResultBuffer, using generator: inout SplitMix64
  ) -> Action {
    let roles = buffer.document.session.inputs.roles
    let block = Int.random(in: 0..<max(buffer.blocks.count, 1), using: &generator)
    guard !buffer.blocks.isEmpty else { return .type("x", 0..<0) }
    switch Int.random(in: 0..<16, using: &generator) {
    case 0..<5:
      let length = buffer.text.utf16.count
      let text = ["", "x", "\n", "ä", "yz\n", "\r\n"].randomElement(using: &generator) ?? ""
      let start = Int.random(in: 0...length, using: &generator)
      let end = Int.random(in: start...min(length, start + 8), using: &generator)
      return .type(text, start..<end)
    case 5: return .moveCursor
    case 6..<8: return .toggle(roles.randomElement(using: &generator) ?? .a, block: block)
    case 8:
      let chosen = (0..<Int.random(in: 0...3, using: &generator)).compactMap { _ in
        roles.randomElement(using: &generator)
      }
      return .choose(chosen, block: block)
    case 9: return .resolveByHand(block: block)
    case 10: return .reset(block: block)
    case 11: return .resetAll
    case 12: return .undo
    default:
      return .restore(
        inOtherComparison: Bool.random(using: &generator),
        currentBlock: Int.random(in: -1..<buffer.blocks.count, using: &generator))
    }
  }
}

extension ResultBuffer {
  /// Takes `action`, which is no restoration.
  fileprivate mutating func carryOut(_ action: MergeWorkFuzzTests.Action) {
    switch action {
    case .type(let text, let range): type(text, replacing: range)
    case .moveCursor: moveCursor()
    case .toggle(let role, let index): perform(document.planToggling(role, in: blocks[index]))
    case .choose(let roles, let index): perform(document.planChoosing(roles, in: blocks[index]))
    case .resolveByHand(let index): perform(document.planResolvingByHand(blocks[index]).plan)
    case .reset(let index): perform(document.planResetting(blocks[index]))
    case .resetAll: perform(document.planResettingAll())
    case .undo: undo()
    case .restore: preconditionFailure("Restoring needs the comparisons of the merge")
    }
  }
}
