import AppKit
import PaneKit
import Testing

@testable import SeamergeUI

extension LargeFileRun {
  /// Copies a change of a comparison to the right, with the button at the seam and with the key
  /// of block mode, each until the window shows the comparison after the copy and is laid out
  /// and drawn, and undoes each copy until the window shows the comparison before it; with the
  /// longest hold of the main actor meanwhile.
  func measureCopying() async throws {
    guard !largeCase.isMerge, controller.canPerform(.copyAllChangesToRight) else { return }
    let presentation = controller.presentation
    let undoManager = controller.sessionUndoManager
    let left = try #require(controller.layout.sourcePane(presentation.arrangement.leadingRole))
    for (metric, byKey) in [("copy-click", false), ("copy-key", true)] {
      presentation.jump(to: presentation.changes.blocks.count / 2)
      contentView.layoutSubtreeIfNeeded()
      let block = try #require(presentation.currentBlock)
      let seam = try #require(controller.layout.seams.first)
      let button = try #require(
        seam.copyButtons.first { $0.block == block && $0.direction == .toRight })
      window.makeFirstResponder(left.documentView)
      let start = clock.now
      let held = try await longestHold {
        if byKey {
          try press(SessionCommand.rightArrow, in: controller)
        } else {
          button.performClick(nil)
        }
        await controller.copying?.value
        contentView.layoutSubtreeIfNeeded()
      }
      recorder.record(metric, clock.now - start)
      draw()
      recorder.record("\(metric)-drawn", clock.now - start)
      recorder.record("\(metric)-longest-hold", held)
      pause()

      let undoStart = clock.now
      let undoHeld = await longestHold {
        undoManager.undo()
        await controller.comparisonSwitcher.bringingBack?.value
        contentView.layoutSubtreeIfNeeded()
      }
      recorder.record("\(metric)-undo", clock.now - undoStart)
      draw()
      recorder.record("\(metric)-undo-drawn", clock.now - undoStart)
      recorder.record("\(metric)-undo-longest-hold", undoHeld)
      pause()
    }
  }
}
