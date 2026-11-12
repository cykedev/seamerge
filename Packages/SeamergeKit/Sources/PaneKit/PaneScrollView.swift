import AppKit

/// The scroll view of a pane: the system's scrollers and gestures, without a vertical scroller,
/// which is the overview bar beside it, if any.
final class PaneScrollView: NSScrollView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    hasVerticalScroller = false
    hasHorizontalScroller = false
    autohidesScrollers = false
    borderType = .noBorder
    drawsBackground = true
    backgroundColor = Theme.backgroundColor
    // Panes on one grid scroll together, and a pane bouncing on its own would leave the rows of
    // its neighbors.
    verticalScrollElasticity = .none
    // A find bar above the text would push its rows down against those of the neighbors.
    findBarPosition = .belowContent
    contentView.postsBoundsChangedNotifications = true
  }

  /// Scroll views of panes are never archived.
  required init?(coder: NSCoder) {
    nil
  }
}
