/// Learns which match a search over several panes shows, when its matches change, and when it
/// replaces text.
@MainActor
package protocol PaneSearchDelegate: AnyObject {
  /// Tells the delegate that `search` brought `match` into view in its pane, after Find Next,
  /// Find Previous or a search as the user types: the moment to make the block of the match the
  /// current one.
  ///
  /// The pane has scrolled, and the panes coupled with it along with it; a collapsed run around
  /// the match has been asked to expand through the pane's delegate.
  func paneSearch(_ search: PaneSearch, didReveal match: PaneSearch.Match)

  /// Tells the delegate that the matches of `search` changed, which ``PaneSearch/matches`` lists,
  /// as the find bar finds them while the user types and once it closes.
  func paneSearchDidChangeMatches(_ search: PaneSearch)

  /// Tells the delegate that `search` is about to replace matches in its editable pane, one or
  /// all of them.
  ///
  /// The edits that follow pass through the pane's editing delegate as typing does, until
  /// ``paneSearch(_:didReplaceAll:)``: an owner that joins steps of typing for undo takes them
  /// as one step of their own instead.
  func paneSearchWillReplace(_ search: PaneSearch)

  /// Tells the delegate that `search` has replaced the matches it began to replace, all of the
  /// matches if `replacesAll` is set, else the current one.
  ///
  /// The search ends its group of undo right after, under the name that
  /// ``PaneSearch/undoActionName(replacingAll:)`` gives.
  func paneSearch(_ search: PaneSearch, didReplaceAll replacesAll: Bool)
}
