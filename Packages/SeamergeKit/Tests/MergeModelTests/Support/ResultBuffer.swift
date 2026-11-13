import Foundation
import MergeModel
import Testing

/// The text of a merge result as the result pane holds it: it carries out the plans of its
/// document and keeps the undo and redo stacks.
struct ResultBuffer {
  /// The document whose plans the buffer carries out.
  private(set) var document: ResultDocument

  /// The result text.
  private(set) var text: String

  /// The steps to undo, the last one first.
  private(set) var undoStack: [UndoStep] = []

  /// The steps to redo, the last one first.
  private(set) var redoStack: [UndoStep] = []

  /// Whether typing continues the last undo step, as it does until a command or a move of the
  /// cursor.
  private var continuesTyping = false

  /// A buffer with the result of `session` as loaded, whose previews show `removalNotes`.
  init(_ session: Session, removalNotes: [Role: String] = [:]) {
    document = ResultDocument(session: session, removalNotes: removalNotes)
    text = document.initialText
  }

  /// The blocks of the session.
  var blocks: [Block] { document.session.blocks }

  /// The text of a block's segment.
  func text(of block: Block) -> String {
    text.utf16Substring(document.range(of: block))
  }

  /// The text of each segment.
  var segmentTexts: [String] { blocks.map(text(of:)) }

  /// Replaces `range` with `replacement` as typing does, and returns the plan.
  @discardableResult
  mutating func type(_ replacement: String, replacing range: Range<Int>) -> EditPlan {
    let plan = document.plan(for: TextReplacement(range: range, text: replacement))
    guard !plan.isEmpty else { return plan }
    let step = carryOut(plan)
    if continuesTyping, let last = undoStack.last, let joined = last.coalesced(with: step) {
      undoStack[undoStack.count - 1] = joined
    } else {
      undoStack.append(step)
    }
    redoStack = []
    continuesTyping = true
    return plan
  }

  /// Inserts `insertion` at `offset` as typing does, and returns the plan.
  @discardableResult
  mutating func type(_ insertion: String, at offset: Int) -> EditPlan {
    type(insertion, replacing: offset..<offset)
  }

  /// Ends the current typing step, as a move of the cursor or a pause does.
  mutating func moveCursor() {
    continuesTyping = false
  }

  /// Carries out the plan of a command as one undo step.
  mutating func perform(_ plan: EditPlan) {
    continuesTyping = false
    guard !plan.isEmpty else { return }
    undoStack.append(carryOut(plan))
    redoStack = []
  }

  /// Takes back the last step.
  mutating func undo() {
    continuesTyping = false
    guard let step = undoStack.popLast() else { return }
    redoStack.append(carryOut(step.undoPlan))
  }

  /// Does the last undone step again.
  mutating func redo() {
    continuesTyping = false
    guard let step = redoStack.popLast() else { return }
    undoStack.append(carryOut(step.undoPlan))
  }

  /// Carries out the replacements of `plan` in order and applies it to the document.
  private mutating func carryOut(_ plan: EditPlan) -> UndoStep {
    var replacedTexts: [String] = []
    for replacement in plan.replacements {
      replacedTexts.append(text.utf16Substring(replacement.range))
      text.replaceUTF16Range(replacement.range, with: replacement.text)
    }
    return document.apply(plan, replacedTexts: replacedTexts)
  }

  /// Records an issue for each invariant of the result that does not hold, and returns whether
  /// all of them hold: the segments cover the text, every block has a segment, and an open
  /// conflict holds exactly its preview.
  @discardableResult
  func checkInvariants(
    _ comment: @autoclosure () -> Comment? = nil, sourceLocation: SourceLocation = #_sourceLocation
  ) -> Bool {
    let segments = document.segments
    var holds = segments.count == blocks.count
    holds = holds && segments.reduce(0) { $0 + $1.length } == text.utf16.count
    holds =
      holds
      && blocks.allSatisfy { block in
        document.segment(for: block).state != .open
          || text(of: block) == document.previewText(for: block)
      }
    #expect(holds, comment(), sourceLocation: sourceLocation)
    return holds
  }
}

extension String {
  /// Replaces a UTF-16 range with `replacement`.
  mutating func replaceUTF16Range(_ range: Range<Int>, with replacement: String) {
    let start = utf16.index(startIndex, offsetBy: range.lowerBound)
    let end = utf16.index(start, offsetBy: range.count)
    replaceSubrange(start..<end, with: replacement)
  }
}
