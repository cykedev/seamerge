import AppKit

/// Learns where the user clicks in a pane, supplies its context menu and expands its collapsed
/// runs.
@MainActor
public protocol PaneViewDelegate: AnyObject {
  /// Tells the delegate that the user clicked `hit` in the text or the gutter of `pane`, after
  /// the pane has handled the click.
  func pane(_ pane: PaneView, didClick hit: PaneHit)

  /// The context menu for a secondary click on `hit`, or `nil` for no menu.
  ///
  /// The menu replaces the standard menu of the text view.
  func pane(_ pane: PaneView, menuFor hit: PaneHit) -> NSMenu?

  /// Tells the delegate that the user asked to expand `run` of `pane`: with a click on its bar,
  /// with Return or Space while the bar has focus, with VoiceOver, or with a find result in it.
  ///
  /// The pane leaves the run collapsed; to expand it, take it out of the collapsed runs of every
  /// pane that shows it.
  func pane(_ pane: PaneView, didAskToExpand run: CollapsedRun)
}
