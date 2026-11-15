import AppKit
import MergeModel
import PaneKit

/// The search of the window: one find bar below the panes for all of them, which Find… opens
/// over every pane in view and Find and Replace… over the result alone, the only text that can
/// be replaced in.
extension SessionWindowController {
  /// Opens the find bar, without the field for replacing, and searches all panes in view.
  ///
  /// The finder opens the bar as it closed it last, with the field for replacing if it was
  /// replacing then; Find takes the field away again, and with it the limit to the result. The
  /// finder searches all panes as soon as the user types; it does not search again on its own.
  @objc func find(_ sender: Any?) {
    guard canPerform(.find) else { return }
    let search = presentation.search
    search.scope = .allPanes
    if search.showsReplaceField {
      search.perform(.hideReplaceInterface)
    }
    search.perform(.showFindInterface)
    if search.showsReplaceField {
      search.perform(.hideReplaceInterface)
    }
  }

  /// Opens the find bar with the field for replacing and limits the search to the result.
  @objc func findAndReplace(_ sender: Any?) {
    guard canPerform(.findAndReplace), let resultPane = layout.resultPane else { return }
    let search = presentation.search
    search.scope = .pane(resultPane)
    search.perform(.showReplaceInterface)
  }

  /// Replaces every match in the result as one step of undo, while the find bar replaces there.
  @objc func replaceAll(_ sender: Any?) {
    guard canPerform(.replaceAll) else { return }
    presentation.search.perform(.replaceAll)
  }

  /// Selects the next match, in the order the panes read; from a pane, the focus goes along to
  /// the pane of the match.
  @objc func findNext(_ sender: Any?) {
    guard canPerform(.findNext) else { return }
    presentation.search.perform(.nextMatch)
  }

  /// Selects the previous match; from a pane, the focus goes along to the pane of the match.
  @objc func findPrevious(_ sender: Any?) {
    guard canPerform(.findPrevious) else { return }
    presentation.search.perform(.previousMatch)
  }

  /// Takes the selection of the pane with the focus as the text to search for.
  @objc func useSelectionForFind(_ sender: Any?) {
    guard canPerform(.useSelectionForFind) else { return }
    presentation.search.perform(.setSearchString)
  }
}

extension SessionWindowController {
  /// Ends the run of typing and gathers the steps of the replacement of the search under way,
  /// which the result reports as typing, into one step of their own.
  func searchWillReplace() {
    typingRun = nil
    replacementSteps = []
  }

  /// Registers the steps of the replacement of the search as one step of undo, named after it:
  /// Replace All if it replaced all matches, else Replace.
  func searchDidReplace(all replacesAll: Bool) {
    let steps = replacementSteps ?? []
    replacementSteps = nil
    typingRun = nil
    guard let first = steps.first else { return }
    guard let joined = steps.dropFirst().reduce(Optional(first), { $0?.coalesced(with: $1) })
    else {
      preconditionFailure("The result reports every replacement as typing, which always joins")
    }
    registerUndo(of: joined, named: PaneSearch.undoActionName(replacingAll: replacesAll))
  }
}
