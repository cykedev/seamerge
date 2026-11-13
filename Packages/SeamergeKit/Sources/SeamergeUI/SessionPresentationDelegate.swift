import AppKit
import MergeModel
import PaneKit

/// Learns what changes in a presentation and supplies what it shows on demand.
@MainActor
protocol SessionPresentationDelegate: AnyObject {
  /// Tells the delegate that another block became current, or none.
  func presentationDidChangeCurrentBlock(_ presentation: SessionPresentation)

  /// Tells the delegate that the result changed, by typing or by a command.
  func presentationDidChangeResult(_ presentation: SessionPresentation)

  /// Tells the delegate that the insertion point or the selection of the result moved to
  /// `selection` by anything but an edit.
  func presentation(
    _ presentation: SessionPresentation, didMoveInsertionPointTo selection: NSRange)

  /// Tells the delegate that the result took over a change of its text that nobody announced,
  /// after which the steps of undo before it no longer fit.
  func presentationDidTakeOverUnannouncedChange(_ presentation: SessionPresentation)

  /// Tells the delegate that the user typed in the result, with the step that takes the typing
  /// back, the range of the pane's text that the typing replaced and the insertion point after
  /// it.
  func presentation(
    _ presentation: SessionPresentation, didType step: UndoStep, at range: Range<Int>, caret: Int)

  /// Tells the delegate that the user switched toggle `toggle` of changed block `block` in the
  /// decision column.
  func presentation(
    _ presentation: SessionPresentation, didAskToSwitchToggle toggle: Int, ofBlock block: Int)

  /// The context menu for a secondary click on `hit` in `pane`.
  func presentation(
    _ presentation: SessionPresentation, menuFor hit: PaneHit, in pane: PaneView
  ) -> NSMenu
}
