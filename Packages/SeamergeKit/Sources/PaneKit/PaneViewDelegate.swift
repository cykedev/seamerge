import AppKit

/// Learns where the user clicks in a pane and supplies its context menu.
@MainActor
public protocol PaneViewDelegate: AnyObject {
  /// Tells the delegate that the user clicked `hit` in the text or the gutter of `pane`, after
  /// the pane has handled the click.
  func pane(_ pane: PaneView, didClick hit: PaneHit)

  /// The context menu for a secondary click on `hit`, or `nil` for no menu.
  ///
  /// The menu replaces the standard menu of the text view.
  func pane(_ pane: PaneView, menuFor hit: PaneHit) -> NSMenu?
}
