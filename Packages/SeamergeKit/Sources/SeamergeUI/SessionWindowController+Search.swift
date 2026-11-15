import AppKit

/// The search of the window: one find bar below the panes for all of them, which Find… opens
/// over every pane in view.
extension SessionWindowController {
  /// Opens the find bar, without the field for replacing, and searches all panes in view.
  @objc func find(_ sender: Any?) {
    guard canPerform(.find) else { return }
    let search = presentation.search
    search.scope = .allPanes
    if search.findBar.isFindBarVisible {
      search.perform(.hideReplaceInterface)
    }
    search.perform(.showFindInterface)
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
