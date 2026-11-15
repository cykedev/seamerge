/// Learns which match a search over several panes shows and when its matches change.
@MainActor
public protocol PaneSearchDelegate: AnyObject {
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
}
