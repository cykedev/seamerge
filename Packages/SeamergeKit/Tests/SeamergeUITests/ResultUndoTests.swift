import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// Undo and redo of the result: one step for each command and each run of typing, restoring
/// text, segments and signs together.
@MainActor
@Suite struct ResultUndoTests {
  /// What the window shows of its result, to compare before and after.
  private struct Snapshot: Equatable {
    let text: String
    let segments: [Segment]
    let decisions: [Int: BlockDecision]
    let paneText: String
    let rowTints: [Int: BlockStyle]

    @MainActor
    init(_ controller: SessionWindowController) throws {
      let result = try controller.presentation.mergeResult
      text = result.text
      segments = result.document.segments
      decisions = try controller.presentation.mergeDecisionColumn.decisions
      paneText = try controller.mergeResult.content.text
      rowTints = try controller.mergeResult.content.rowTints
    }
  }

  @Test func runOfTypingIsOneStep() async throws {
    let controller = try Windows.controller(for: try await EditingFixture.nineBlocks())
    let undoManager = controller.sessionUndoManager
    let before = try Snapshot(controller)
    let textView = try controller.resultTextView
    textView.setSelectedRange(NSRange(location: 4, length: 0))

    for character in ["a", "b", "c"] {
      textView.insertText(character, replacementRange: NSRange(location: NSNotFound, length: 0))
      controller.endEvent()
    }
    textView.deleteBackward(nil)
    controller.endEvent()
    #expect(try controller.segmentTexts[1] == "Aab1\n")
    #expect(undoManager.undoActionName == "Typing")

    undoManager.undo()
    #expect(try Snapshot(controller) == before)
    #expect(!undoManager.canUndo)
    undoManager.redo()
    #expect(try controller.segmentTexts[1] == "Aab1\n")
  }

  @Test func commandMoveOfTheCaretOrPauseEndsTheRunOfTyping() async throws {
    var time = ContinuousClock.now
    let controller = try controller(for: try await EditingFixture.nineBlocks()) { time }
    let undoManager = controller.sessionUndoManager
    let textView = try controller.resultTextView
    let typeAtCaret = { (text: String) in
      textView.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
      controller.endEvent()
    }
    textView.setSelectedRange(NSRange(location: 4, length: 0))
    typeAtCaret("a")
    time += .seconds(3)
    typeAtCaret("b")
    textView.setSelectedRange(NSRange(location: 0, length: 0))
    typeAtCaret("c")

    undoManager.undo()
    #expect(try controller.segmentTexts[0] == "u0\n")
    #expect(try controller.segmentTexts[1] == "Aab1\n")
    undoManager.undo()
    #expect(try controller.segmentTexts[1] == "Aa1\n")
    undoManager.undo()
    #expect(try controller.segmentTexts[1] == "A1\n")
    #expect(!undoManager.canUndo)
  }

  @Test func switchOfTheComparisonEndsTheRunOfTyping() async throws {
    let time = ContinuousClock.now
    let prompts = PromptRecorder()
    prompts.switchesAnyway = true
    let controller = try controller(for: try await EditingFixture.nineBlocks(), prompts: prompts) {
      time
    }
    let undoManager = controller.sessionUndoManager
    let mode = controller.comparisonOptions.mode
    let textView = try controller.resultTextView
    textView.setSelectedRange(NSRange(location: 4, length: 0))
    textView.insertText("a", replacementRange: NSRange(location: NSNotFound, length: 0))
    controller.endEvent()
    await controller.switchComparison(to: ComparisonOptions(mode: .ignoreAllWhitespace))
    controller.endEvent()
    let typing = try controller.resultTextView
    typing.setSelectedRange(NSRange(location: 5, length: 0))
    typing.insertText("b", replacementRange: NSRange(location: NSNotFound, length: 0))
    controller.endEvent()
    #expect(try controller.segmentTexts[1] == "Aab1\n")
    #expect(undoManager.undoActionName == "Typing")

    undoManager.undo()
    #expect(try controller.segmentTexts[1] == "Aa1\n")
    #expect(controller.comparisonOptions.mode == .ignoreAllWhitespace)
    try controller.checkResultIsShownAsModelled()
    undoManager.undo()
    #expect(controller.comparisonOptions.mode == mode)
    undoManager.undo()
    #expect(try controller.segmentTexts[1] == "A1\n")
    try controller.checkResultIsShownAsModelled()
    #expect(!undoManager.canUndo)
  }

  @Test func moveOfTheInsertionPointAwayAndBackEndsTheRunOfTyping() async throws {
    let time = ContinuousClock.now
    let controller = try controller(for: try await EditingFixture.nineBlocks()) { time }
    let undoManager = controller.sessionUndoManager
    let textView = try controller.resultTextView
    textView.setSelectedRange(NSRange(location: 4, length: 0))
    textView.insertText("a", replacementRange: NSRange(location: NSNotFound, length: 0))
    controller.endEvent()
    textView.setSelectedRange(NSRange(location: 0, length: 0))
    textView.setSelectedRange(NSRange(location: 5, length: 0))
    textView.insertText("b", replacementRange: NSRange(location: NSNotFound, length: 0))
    controller.endEvent()

    undoManager.undo()
    #expect(try controller.segmentTexts[1] == "Aa1\n")
  }

  @Test func editOfSeveralSelectionsInOneEventIsOneStep() async throws {
    let controller = try Windows.controller(for: try await EditingFixture.nineBlocks())
    let undoManager = controller.sessionUndoManager
    let before = try Snapshot(controller)
    let textView = try controller.resultTextView

    // An action on several selections, such as Replace All of the find bar, asks for all of
    // them at once.
    #expect(
      !textView.shouldChangeText(
        inRanges: [
          NSValue(range: NSRange(location: 1, length: 0)),
          NSValue(range: NSRange(location: 19, length: 0)),
        ],
        replacementStrings: ["!", "!"]))
    controller.endEvent()
    #expect(try controller.segmentTexts[0] == "u!0\n")
    #expect(try controller.segmentTexts[5] == "B!5\n")

    undoManager.undo()
    #expect(try Snapshot(controller) == before)
    #expect(!undoManager.canUndo)
  }

  /// The controller of a laid-out window for `session` that takes the time from `now`.
  private func controller(
    for session: Session, prompts: PromptRecorder = PromptRecorder(),
    now: @escaping () -> ContinuousClock.Instant
  ) throws -> SessionWindowController {
    let controller = SessionWindowController(
      session: session, context: SessionContext(), undoManager: UndoManager(),
      displayOptions: DisplayOptions(reducesMotion: true), pasteboard: .withUniqueName(),
      workspace: WorkspaceRecorder(), prompts: prompts, doneStyle: .standard,
      window: SessionWindow(), now: now)
    try #require(controller.window).contentView?.layoutSubtreeIfNeeded()
    return controller
  }
}
