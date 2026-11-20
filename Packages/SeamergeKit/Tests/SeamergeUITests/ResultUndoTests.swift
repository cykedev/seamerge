import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// Undo and redo of the result: one step for each command and each run of typing, restoring
/// text, segments and signs together; and resetting in three reaches.
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

  @Test(arguments: [
    SessionCommand.useA, .useBase, .useB, .useAThenB, .useBThenA, .useNone, .toggleSourceA,
    .toggleSourceB, .resolveManually, .resolveAllWithA, .resolveAllWithB,
  ])
  func undoAfterACommandRestoresTextStatesAndSignsAndRedoDoesItAgain(
    command: SessionCommand
  ) async throws {
    let controller = try Windows.controller(for: try await EditingFixture.nineBlocks())
    let undoManager = controller.sessionUndoManager
    controller.presentation.setCurrentBlock(1)
    let before = try Snapshot(controller)

    controller.perform(command)
    controller.endEvent()
    let after = try Snapshot(controller)
    #expect(after != before)
    #expect(undoManager.undoActionName == command.undoName)

    undoManager.undo()
    #expect(try Snapshot(controller) == before)
    try controller.checkResultIsShownAsModelled()
    undoManager.redo()
    #expect(try Snapshot(controller) == after)
    try controller.checkResultIsShownAsModelled()
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

  @Test func commandOfAMenuEndsTheRunOfTyping() async throws {
    let controller = try Windows.controller(for: try await EditingFixture.nineBlocks())
    let undoManager = controller.sessionUndoManager
    let textView = try controller.resultTextView
    let menu = NSMenu()
    let target = MenuTarget()
    let item = menu.addItem(
      withTitle: "Nothing", action: #selector(MenuTarget.doNothing(_:)), keyEquivalent: "")
    item.target = target
    textView.setSelectedRange(NSRange(location: 4, length: 0))

    textView.insertText("a", replacementRange: NSRange(location: NSNotFound, length: 0))
    controller.endEvent()
    menu.performActionForItem(at: 0)
    textView.insertText("b", replacementRange: NSRange(location: NSNotFound, length: 0))
    controller.endEvent()

    undoManager.undo()
    #expect(try controller.segmentTexts[1] == "Aa1\n")
    undoManager.undo()
    #expect(try controller.segmentTexts[1] == "A1\n")
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
    await controller.comparisonSwitcher.bringingBack?.value
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

  @Test func resettingEverythingGivesTheWindowAsOpenedAndIsOneStep() async throws {
    let session = try await EditingFixture.nineBlocks()
    let prompts = PromptRecorder()
    prompts.resetsAnyway = true
    let controller = try Windows.controller(for: session, prompts: prompts)
    let fresh = try Snapshot(try Windows.controller(for: session))
    controller.presentation.setCurrentBlock(1)
    controller.perform(.useA)
    controller.endEvent()
    controller.presentation.setCurrentBlock(0)
    controller.perform(.useB)
    controller.endEvent()
    let decided = try Snapshot(controller)

    // Without text typed by hand, nothing asks.
    await controller.resetEveryDecision()
    controller.endEvent()
    #expect(prompts.discardedHandwritingCounts.isEmpty)
    #expect(try Snapshot(controller) == fresh)
    #expect(!controller.canPerform(.resetAllDecisions))
    let fresher = try Windows.controller(for: session)
    #expect(
      try controller.mergeResult.content.blocks == fresher.mergeResult.content.blocks)
    #expect(
      try controller.presentation.mergeResultOverviewBar.marks
        == fresher.presentation.mergeResultOverviewBar.marks)
    #expect(
      controller.presentation.sourcesOverviewBar.marks
        == fresher.presentation.sourcesOverviewBar.marks)

    controller.sessionUndoManager.undo()
    #expect(try Snapshot(controller) == decided)
  }

  @Test func resettingEverythingAsksOnlyWhenHandwritingWouldBeLost() async throws {
    let prompts = PromptRecorder()
    let controller = try Windows.controller(
      for: try await EditingFixture.nineBlocks(), prompts: prompts)
    try controller.type("x", over: 4..<4, with: .insertText)
    try controller.type("y", over: 16..<16, with: .insertText)
    controller.endEvent()
    let typed = try Snapshot(controller)

    await controller.resetEveryDecision()
    #expect(prompts.discardedHandwritingCounts == [2])
    #expect(try Snapshot(controller) == typed)

    prompts.resetsAnyway = true
    await controller.resetEveryDecision()
    #expect(try controller.presentation.mergeResult.text == EditingFixture.loadedText)
  }

  @Test func reopeningTheConflictsLeavesTheOtherBlocks() async throws {
    let controller = try Windows.controller(for: try await EditingFixture.nineBlocks())
    controller.perform(.resolveAllWithA)
    controller.presentation.setCurrentBlock(0)
    controller.perform(.useB)
    #expect(controller.canPerform(.reopenAllConflicts))

    controller.perform(.reopenAllConflicts)

    let states = try controller.segmentStates
    #expect(states[3] == .open && states[7] == .open)
    #expect(states[1] == .chosen)
    #expect(!controller.canPerform(.reopenAllConflicts))
    try controller.checkResultIsShownAsModelled()
  }

  @Test func resettingTheBlockWithItsArrowReturnsItAsLoaded() async throws {
    let controller = try Windows.controller(for: try await EditingFixture.nineBlocks())
    let column = try controller.presentation.mergeDecisionColumn
    try controller.type("typed", over: 4..<4, with: .insertText)
    #expect(controller.canPerform(.resetChange))

    controller.presentation.decisionColumn(column, didAskToResetBlock: 0)

    #expect(try controller.segmentTexts[1] == "A1\n")
    #expect(try controller.segmentStates[1] == .auto)
    #expect(!controller.canPerform(.resetChange))
    #expect(column.decisions[0]?.canReset == false)
    try controller.checkResultIsShownAsModelled()
  }

  @Test func commandsToResetAreValidOnlyWhenThereIsSomethingToReset() async throws {
    let controller = try Windows.controller(for: try await EditingFixture.nineBlocks())
    controller.presentation.setCurrentBlock(0)
    #expect(!controller.canPerform(.resetChange))
    #expect(!controller.canPerform(.reopenAllConflicts))
    #expect(!controller.canPerform(.resetAllDecisions))

    controller.perform(.useB)
    #expect(controller.canPerform(.resetChange))
    #expect(!controller.canPerform(.reopenAllConflicts))
    #expect(controller.canPerform(.resetAllDecisions))
    controller.presentation.setCurrentBlock(1)
    controller.perform(.useA)
    #expect(controller.canPerform(.reopenAllConflicts))
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
      settings: .private(), window: SessionWindow(), now: now)
    try #require(controller.window).contentView?.layoutSubtreeIfNeeded()
    return controller
  }
}

/// The target of a command of a menu that does nothing.
private final class MenuTarget: NSObject {
  @objc func doNothing(_ sender: Any?) {}
}
