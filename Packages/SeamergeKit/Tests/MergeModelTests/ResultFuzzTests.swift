import MergeModel
import Testing

/// Random sequences of edits, decisions, resets, mode switches, undo and redo.
struct ResultFuzzTests {
  /// One action on a result, as a user may take it.
  enum Action: CustomStringConvertible {
    case type(String, Range<Int>)
    case moveCursor
    case toggle(Role, block: Int)
    case choose([Role], block: Int)
    case resolveOpenConflicts([Role])
    case resolveByHand(block: Int)
    case reset(block: Int)
    case resetConflicts
    case resetAll
    case switchMode
    case undo
    case redo

    var description: String {
      switch self {
      case .type(let text, let range): "type \(text.debugDescription) over \(range)"
      case .moveCursor: "move cursor"
      case .toggle(let role, let block): "toggle \(role) in \(block)"
      case .choose(let roles, let block): "choose \(roles) in \(block)"
      case .resolveOpenConflicts(let roles): "resolve open conflicts with \(roles)"
      case .resolveByHand(let block): "resolve \(block) by hand"
      case .reset(let block): "reset \(block)"
      case .resetConflicts: "reset conflicts"
      case .resetAll: "reset all"
      case .switchMode: "switch mode"
      case .undo: "undo"
      case .redo: "redo"
      }
    }
  }

  @Test func randomSequencesKeepTheInvariantsAndUndoBackToTheStart() async throws {
    let seed: UInt64 = 2026
    var generator = SplitMix64(seed: seed)
    // Comparing is asynchronous, so the sequences share a pool of sessions, each with a second
    // comparison of the same files to switch to.
    var pairs: [(Session, Session)] = []
    for _ in 0..<200 {
      let input = RandomMergeInput(using: &generator)
      let modes = ComparisonMode.allCases.shuffled(using: &generator)
      pairs.append(
        (
          try await input.session(mode: modes[0], strategy: .optimal),
          try await input.session(mode: modes[1], strategy: .guarded)
        ))
    }

    for sequence in 0..<10_000 {
      let pair = pairs[sequence % pairs.count]
      var buffer = ResultBuffer(pair.0)
      var actions: [Action] = []
      for _ in 0..<12 {
        let action = Self.randomAction(for: buffer, using: &generator)
        actions.append(action)
        let openBlocks = buffer.openBlocks
        let takesTyping = buffer.document.segments.contains { $0.state != .open }
        let typingPlan = buffer.carryOut(action, switchingBetween: pair)
        let context = Comment(rawValue: "seed \(seed), sequence \(sequence), \(actions)")
        guard buffer.checkInvariants(context) else { return }
        if case .type(let text, _) = action {
          // Typing never resolves an open conflict and is never refused while a segment without
          // a preview can take it.
          try #require(buffer.openBlocks == openBlocks, context)
          try #require(text.isEmpty || !takesTyping || typingPlan?.isEmpty == false, context)
        }
      }

      let final = (text: buffer.text, segments: buffer.document.segments)
      let stepCount = buffer.undoStack.count
      for _ in 0..<stepCount {
        buffer.undo()
      }
      let context = Comment(rawValue: "seed \(seed), sequence \(sequence), \(actions)")
      #expect(buffer.text == ResultDocument(session: pair.0).initialText, context)
      #expect(buffer.document.segments == ResultDocument(session: pair.0).segments, context)
      for _ in 0..<stepCount {
        buffer.redo()
      }
      #expect(buffer.text == final.text, context)
      #expect(buffer.document.segments == final.segments, context)
    }
  }

  /// An action that suits the state of `buffer`.
  private static func randomAction(
    for buffer: ResultBuffer, using generator: inout SplitMix64
  ) -> Action {
    let roles = buffer.document.session.inputs.roles
    let block = Int.random(in: 0..<max(buffer.blocks.count, 1), using: &generator)
    func someRoles() -> [Role] {
      (0..<Int.random(in: 0...3, using: &generator)).compactMap { _ in
        roles.randomElement(using: &generator)
      }
    }
    guard !buffer.blocks.isEmpty else { return .type("x", 0..<0) }
    switch Int.random(in: 0..<20, using: &generator) {
    case 0..<7:
      let length = buffer.text.utf16.count
      let text = ["", "x", "\n", "ä", "yz\n", "\r\n"].randomElement(using: &generator) ?? ""
      // Now and then everything is selected, as with Select All.
      if Int.random(in: 0..<8, using: &generator) == 0 {
        return .type(text, 0..<length)
      }
      let start = Int.random(in: 0...length, using: &generator)
      let end = Int.random(in: start...min(length, start + 8), using: &generator)
      return .type(text, start..<end)
    case 7: return .moveCursor
    case 8..<11: return .toggle(roles.randomElement(using: &generator) ?? .a, block: block)
    case 11: return .choose(someRoles(), block: block)
    case 12: return .resolveOpenConflicts(someRoles())
    case 13: return .resolveByHand(block: block)
    case 14: return .reset(block: block)
    case 15: return .resetConflicts
    case 16: return .resetAll
    case 17: return .switchMode
    case 18: return .undo
    default: return .redo
    }
  }
}

extension ResultBuffer {
  /// The numbers of the blocks whose conflict is open.
  fileprivate var openBlocks: [Int] {
    blocks.filter { document.segment(for: $0).state == .open }.map(\.id)
  }

  /// Takes `action`, and returns the plan if the action is typing; a mode switch goes to the
  /// session of `pair` that is not current.
  fileprivate mutating func carryOut(
    _ action: ResultFuzzTests.Action, switchingBetween pair: (Session, Session)
  ) -> EditPlan? {
    func block(_ index: Int) -> Block { blocks[index] }
    switch action {
    case .type(let text, let range): return type(text, replacing: range)
    case .moveCursor: moveCursor()
    case .toggle(let role, let index): perform(document.planToggling(role, in: block(index)))
    case .choose(let roles, let index): perform(document.planChoosing(roles, in: block(index)))
    case .resolveOpenConflicts(let roles): perform(document.planResolvingOpenConflicts(with: roles))
    case .resolveByHand(let index): perform(document.planResolvingByHand(block(index)).plan)
    case .reset(let index): perform(document.planResetting(block(index)))
    case .resetConflicts: perform(document.planResettingConflicts())
    case .resetAll: perform(document.planResettingAll())
    case .switchMode:
      let target = document.session.options == pair.0.options ? pair.1 : pair.0
      perform(document.planSwitching(to: target, text: text).plan)
    case .undo: undo()
    case .redo: redo()
    }
    return nil
  }
}
