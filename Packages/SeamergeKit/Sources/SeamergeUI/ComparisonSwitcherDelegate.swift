/// Shows what a comparison switcher brings back, and what the comparison under way changes in
/// the window.
@MainActor
protocol ComparisonSwitcherDelegate: AnyObject {
  /// The comparison that the window shows now, as undo and redo bring it back.
  func shownComparison(for switcher: ComparisonSwitcher) -> ShownComparison

  /// Shows `comparison` again, whose panes `prepared` holds, as no step of undo; `copy` tells
  /// the copy that the step takes back or carries out again, if it is one.
  func comparisonSwitcher(
    _ switcher: ComparisonSwitcher, bringsBack comparison: ShownComparison,
    as prepared: PreparedSession, copy: CopyReturn?)

  /// Says that the window brings back an earlier comparison, and takes no command of the lines
  /// until it shows.
  func comparisonSwitcherDidBeginBringingBack(_ switcher: ComparisonSwitcher)

  /// Says that a comparison begins, during which no copy of a change can begin.
  func comparisonSwitcherDidBegin(_ switcher: ComparisonSwitcher)

  /// Says that the comparison under way takes a moment.
  func comparisonSwitcherTakesAMoment(_ switcher: ComparisonSwitcher)

  /// Says that the comparison under way ended, and looks at what changed meanwhile.
  func comparisonSwitcherDidEnd(_ switcher: ComparisonSwitcher)
}
