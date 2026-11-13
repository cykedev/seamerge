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

  /// Tells the delegate that the result took over a change of its text that nobody announced,
  /// after which the steps of undo before it no longer fit.
  func presentationDidTakeOverUnannouncedChange(_ presentation: SessionPresentation)

  /// The context menu for a secondary click on `hit` in `pane`.
  func presentation(
    _ presentation: SessionPresentation, menuFor hit: PaneHit, in pane: PaneView
  ) -> NSMenu
}
