import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// Random sequences of typing, decisions, resets, undo and redo in the window, against the
/// invariants of the result: the text of the result pane is always the text of the model, every
/// block keeps exactly one segment, an open conflict holds its preview, typing never resolves a
/// conflict, and undo leads back to the start.
@MainActor
@Suite struct ResultFuzzTests {
  private static let pieces = ["a", "bc", "\n", "x\ny", "", "é"]

  private static let commands: [SessionCommand] = [
    .useA, .useBase, .useB, .useAThenB, .useBThenA, .useNone, .toggleSourceA,
    .toggleSourceBase, .toggleSourceB, .resolveManually, .resetChange, .reopenAllConflicts,
    .resolveAllWithA, .resolveAllWithB,
  ]

  @Test func randomSequencesKeepTheResultAndItsPaneInStep() async throws {
    let seed: UInt64 = 1608
    var generator = SeededGenerator(seed: seed)
    let session = try await EditingFixture.nineBlocks()
    // One window for all sequences: each starts where undoing the one before led back to.
    let controller = try Windows.controller(for: session)
    let undoManager = controller.sessionUndoManager
    for sequence in 0..<2000 {
      for step in 0..<6 {
        let context: Comment = "seed \(seed), sequence \(sequence), step \(step)"
        let openBefore = try controller.presentation.mergeResult.document.openConflictCount
        let typed = try act(on: controller, using: &generator)
        controller.endEvent()
        // Lays the text out, as the window does after each event on the screen.
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        try controller.mergeResult.documentView.textLayoutManager?.textViewportLayoutController
          .layoutViewport()
        try controller.checkResultIsShownAsModelled(context)
        let document = try controller.presentation.mergeResult.document
        #expect(document.segments.count == session.blocks.count, context)
        if typed {
          #expect(document.openConflictCount == openBefore, context)
        }
      }
      while undoManager.canUndo {
        undoManager.undo()
      }
      let context: Comment = "seed \(seed), sequence \(sequence), undone"
      #expect(try controller.presentation.mergeResult.text == EditingFixture.loadedText, context)
      try controller.checkResultIsShownAsModelled(context)
      controller.leaveTextMode()
    }
  }

  /// Carries out a random action on the window and returns whether it was typing.
  private func act(
    on controller: SessionWindowController, using generator: inout SeededGenerator
  ) throws -> Bool {
    let undoManager = controller.sessionUndoManager
    switch Int.random(in: 0..<10, using: &generator) {
    case 0..<4:
      let length = try controller.mergeResult.content.text.utf16.count
      let first = Int.random(in: 0...length, using: &generator)
      let second = Int.random(in: 0...length, using: &generator)
      let text = (0..<Int.random(in: 0...2, using: &generator)).map { _ in
        Self.pieces.randomElement(using: &generator) ?? ""
      }.joined()
      let input = Input.allCases.randomElement(using: &generator) ?? .insertText
      try controller.type(text, over: min(first, second)..<max(first, second), with: input)
      return true
    case 4..<7:
      let blocks = controller.presentation.changes.blocks.indices
      controller.presentation.setCurrentBlock(blocks.randomElement(using: &generator))
      if let command = Self.commands.randomElement(using: &generator) {
        controller.perform(command)
      }
      if controller.isInTextMode && Bool.random(using: &generator) {
        controller.leaveTextMode()
      }
    case 7, 8:
      if undoManager.canUndo { undoManager.undo() }
    default:
      if undoManager.canRedo { undoManager.redo() }
    }
    return false
  }
}
