import AppKit
import MergeModel

/// Resetting decisions in three reaches: the current block, every conflict, or every block.
/// Each is one step of undo.
extension SessionWindowController {
  /// Returns the current block to how it was after loading, without asking: Undo brings it back.
  @objc func resetChange(_ sender: Any?) {
    guard canPerform(.resetChange), let block = currentResultBlock,
      let document = presentation.result?.document
    else { return }
    carryOut(document.planResetting(block), named: SessionCommand.resetChange.undoName ?? "")
    if let current = presentation.currentBlock {
      announceState(ofBlock: current)
    }
  }

  /// Opens every conflict again and leaves the other blocks as they are.
  @objc func reopenAllConflicts(_ sender: Any?) {
    guard canPerform(.reopenAllConflicts), let document = presentation.result?.document else {
      return
    }
    let name = SessionCommand.reopenAllConflicts.undoName ?? ""
    carryOut(document.planResettingConflicts(), named: name)
    announceOutcome(name)
  }

  /// Returns every block to how it was after loading, so that the window shows the merge as it
  /// opened, scrolled where it is; a sheet asks first if text typed by hand would be lost.
  @objc func resetAllDecisions(_ sender: Any?) {
    Task { await resetEveryDecision() }
  }

  /// Resets every decision, after asking if text typed by hand would be lost.
  func resetEveryDecision() async {
    guard canPerform(.resetAllDecisions), let document = presentation.result?.document else {
      return
    }
    let editedCount = document.editedBlockCount
    if editedCount > 0 {
      guard let window,
        await prompts.confirmResettingAll(discardingHandwritingIn: editedCount, in: window)
      else { return }
    }
    // The document may have changed while the sheet was up.
    guard let current = presentation.result?.document else { return }
    let name = SessionCommand.resetAllDecisions.undoName ?? ""
    carryOut(current.planResettingAll(), named: name)
    announceOutcome(name)
  }
}
