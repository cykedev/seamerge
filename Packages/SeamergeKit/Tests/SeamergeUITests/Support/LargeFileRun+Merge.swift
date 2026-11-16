import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// The phases that only a merge goes through: deciding and typing in the result.
extension LargeFileRun {
  /// Measures taking B into a conflict, jumping to the next conflict and typing in the result,
  /// as the window shows the lines now, and undoes all of it afterwards.
  ///
  /// - Parameter label: Says how the window shows the lines, for the names of the metrics.
  func measureDecidingAndTyping(_ label: String) throws {
    let result = try controller.presentation.mergeResult
    let openConflicts = controller.presentation.navigation.openConflictCount
    controller.perform(.firstChange)
    // Each toggle is undone, so that every conflict stays open and the jumps go on through them.
    let undoManager = controller.sessionUndoManager
    measure(
      "toggle-source-\(label)", .steps,
      prepare: {
        controller.endEvent()
        if undoManager.canUndo { undoManager.undo() }
      },
      action: { controller.perform(.toggleSourceB) })
    controller.endEvent()
    undoManager.undo()
    measure(
      "jump-next-conflict-\(label)", .steps, prepare: { controller.endEvent() },
      action: { controller.perform(.nextConflict) })

    let textView = try controller.resultTextView
    let pane = try controller.mergeResult
    let blocks = pane.content.blocks
    // The row after the block nearest the middle: shown also with collapsed lines, as context.
    let middle = pane.content.offset(ofRow: blocks[blocks.count / 2].rows.upperBound)
    for place in ["middle", "end"] {
      let offset = place == "middle" ? middle : (textView.string as NSString).length
      textView.setSelectedRange(NSRange(location: offset, length: 0))
      textView.scrollRangeToVisible(textView.selectedRange())
      controller.endEvent()
      measure(
        "typing-\(place)-\(label)", .steps, prepare: { controller.endEvent() },
        action: {
          textView.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
        })
    }

    controller.endEvent()
    while undoManager.canUndo {
      undoManager.undo()
      controller.endEvent()
    }
    contentView.layoutSubtreeIfNeeded()
    #expect(try controller.presentation.mergeResult.text == result.text)
    #expect(controller.presentation.navigation.openConflictCount == openConflicts)
  }
}
