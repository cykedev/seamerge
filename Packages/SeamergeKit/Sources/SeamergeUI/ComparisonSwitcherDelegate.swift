/// Shows what a comparison switcher brings back, and what the comparison under way changes in
/// the window.
@MainActor
protocol ComparisonSwitcherDelegate: AnyObject {
  /// The comparison that the window shows now, as undo and redo bring it back.
  func shownComparison(for switcher: ComparisonSwitcher) -> ShownComparison

  /// Shows `comparison` again, whose panes `prepared` holds, as no step of undo.
  func comparisonSwitcher(
    _ switcher: ComparisonSwitcher, bringsBack comparison: ShownComparison,
    as prepared: PreparedSession)

  /// Says that the window brings back an earlier comparison, and takes no command of the lines
  /// until it shows.
  func comparisonSwitcherDidBeginBringingBack(_ switcher: ComparisonSwitcher)

  /// Says that the comparison under way takes a moment.
  func comparisonSwitcherTakesAMoment(_ switcher: ComparisonSwitcher)

  /// Says that the comparison under way ended, and looks at what changed meanwhile.
  func comparisonSwitcherDidEnd(_ switcher: ComparisonSwitcher)
}
