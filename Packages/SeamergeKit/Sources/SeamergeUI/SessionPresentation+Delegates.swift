import AppKit
import PaneKit

extension SessionPresentation: PaneViewDelegate {
  /// A click on a row of a changed block makes the block current; the click still places the
  /// insertion point and selects text as in any text.
  func pane(_ pane: PaneView, didClick hit: PaneHit) {
    select(hit, in: pane)
  }

  /// A secondary click first makes the block under the pointer current, as a click does, then
  /// shows the menu of the delegate in place of the text view's standard one, which holds
  /// commands that do not apply to a session.
  func pane(_ pane: PaneView, menuFor hit: PaneHit) -> NSMenu? {
    select(hit, in: pane)
    return delegate?.presentation(self, menuFor: hit, in: pane)
  }

  /// Expands the run in every pane that shows it.
  func pane(_ pane: PaneView, didAskToExpand run: CollapsedRun) {
    let row = gridRow(ofRow: run.rows.lowerBound, in: pane)
    guard let collapsedRun = collapsed.run(containingRow: row) else { return }
    collapsed.expand(collapsedRun)
    showCollapsedRuns()
  }

  /// Collapses the run again in every pane that shows it, says so and leaves the focus on its
  /// bar in `pane`.
  func pane(_ pane: PaneView, didAskToCollapse run: CollapsedRun) {
    let row = gridRow(ofRow: run.rows.lowerBound, in: pane)
    guard let expandedRun = collapsed.expandedRuns.first(where: { $0.rows.contains(row) }),
      collapsed.collapse(expandedRun)
    else { return }
    showCollapsedRuns()
    if let bar = pane.collapsedRuns.first(where: { $0.rows.contains(run.rows.lowerBound) }) {
      pane.focusBar(of: bar)
    }
    announce(
      String(
        localized: "Collapsed \(run.rows.count) unchanged lines", bundle: .module,
        comment: "VoiceOver: a run of unchanged lines was hidden again, such as 12."))
  }
}

extension SessionPresentation: OverviewBarDelegate {
  /// A click on a mark makes its block current; the bar scrolls to it on its own.
  func overviewBar(_ overviewBar: OverviewBar, didSelectBlock block: Int) {
    setCurrentBlock(block)
  }
}

extension SessionPresentation: DecisionColumnDelegate {
  /// A toggle switches the source of its block on or off, as its command does.
  func decisionColumn(
    _ column: DecisionColumnView, didSwitchToggle toggle: Int, ofBlock block: Int
  ) {
    delegate?.presentation(self, didAskToSwitchToggle: toggle, ofBlock: block)
  }

  /// The arrow beside the toggles resets its block, as Reset This Change does.
  func decisionColumn(_ column: DecisionColumnView, didAskToResetBlock block: Int) {
    delegate?.presentation(self, didAskToResetBlock: block)
  }

  /// A click beside a block makes it current, as a click on its rows does.
  func decisionColumn(_ column: DecisionColumnView, didClickBlock block: Int) {
    guard let resultPane = layout.resultPane else { return }
    select(
      PaneHit(row: resultPane.content.blocks[block].rows.lowerBound, block: block), in: resultPane)
  }
}
