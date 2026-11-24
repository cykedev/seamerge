import AppKit
import MergeModel

/// The work of a merge kept on disk: put back as the window opens, captured after each step, and
/// removed once the merge is finished.
extension SessionWindowController {
  /// Notes a step of the user that changed the work, which ends the note of restored work in the
  /// subtitle and has the work captured.
  func workDidChange() {
    guard !isRestoringWork, let workKeeper else { return }
    if restoredWork != nil {
      restoredWork = nil
      sessionDidChange()
    }
    workKeeper.workDidChange()
  }

  /// The work in the window as values, or `nil` while the window shows no result whose work it
  /// keeps, such as while it waits for its comparison or says why it cannot show it.
  var workSnapshot: WorkSnapshot? {
    guard case .ready = phase, binaryMerge == nil, let workKeeper, let saving,
      let result = presentation.result
    else { return nil }
    return WorkSnapshot(
      document: result.document, text: result.text, format: saving.format,
      currentBlock: presentation.currentBlock.map { presentation.changes.blocks[$0] },
      savedAt: workKeeper.now())
  }

  /// Whether a session that ends with `outcome` finishes the merge: its result saved as the
  /// window shows it, without open conflicts, so that nothing of the work is left to keep.
  func finishesMerge(_ outcome: SessionOutcome) -> Bool {
    guard case .saved = outcome, saving?.url != nil, !isResultEdited,
      let document = presentation.result?.document
    else { return false }
    return document.openConflictCount == 0
  }

  /// Puts back `earlierWork`, which the folder of work held for the merge as the window opened,
  /// and keeps the work under its key from now on.
  ///
  /// The work goes into the result as loaded as a single step of undo, which takes the result
  /// back to how it opened. The block that was current is current again, the subtitle names the
  /// work until the user takes a step, and VoiceOver hears what is back, once the window shows.
  func restore(_ earlierWork: EarlierWork) {
    workKeeper?.keepWork(as: earlierWork)
    guard let work = earlierWork.work, let saving, let result = presentation.result,
      let restoration = result.document.planRestoring(work), !restoration.plan.isEmpty
    else { return }
    let name = RestoredWork.undoName
    isRestoringWork = true
    sessionUndoManager.beginUndoGrouping()
    resultUndo.carryOut(restoration.plan, named: name)
    if work.format != saving.format {
      setResultFormat(work.format, named: name)
    }
    sessionUndoManager.endUndoGrouping()
    sessionUndoManager.setActionName(name)
    isRestoringWork = false
    if let block = restoration.currentBlock,
      let current = presentation.changes.blocks.firstIndex(of: block)
    {
      presentation.setCurrentBlock(current)
      presentation.showCurrentBlock()
    }
    let restored = RestoredWork(
      savedAt: work.savedAt, restartedBlockCount: restoration.restartedBlockCount)
    restoredWork = restored
    if let document = presentation.result?.document {
      restoredWorkAnnouncement = restored.announcement(
        conflictCount: presentation.changes.blocks.count { $0.kind == .conflict },
        openConflictCount: document.openConflictCount)
    }
    sessionDidChange()
    stateDidChange()
  }

  /// What the subtitle says about the earlier work the window put back, while it does.
  var restoredWorkNote: String? {
    guard let restoredWork, let workKeeper else { return nil }
    return restoredWork.note(
      now: workKeeper.now(), calendar: .autoupdatingCurrent, locale: .autoupdatingCurrent)
  }

  /// Tells VoiceOver of the earlier work the window put back, once, if the window shows.
  func announceRestoredWorkOnce() {
    guard window?.isVisible == true, let announcement = restoredWorkAnnouncement else { return }
    restoredWorkAnnouncement = nil
    presentation.announce(announcement)
  }
}
