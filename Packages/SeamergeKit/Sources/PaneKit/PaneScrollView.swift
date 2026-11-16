import AppKit

/// The scroll view of a pane: the system's scrollers and gestures, without a vertical scroller,
/// which is the overview bar beside it, if any.
final class PaneScrollView: NSScrollView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    contentView = PaneClipView()
    hasVerticalScroller = false
    hasHorizontalScroller = false
    borderType = .noBorder
    drawsBackground = true
    backgroundColor = Theme.backgroundColor
    // Panes on one grid scroll together, and a pane bouncing on its own would leave the rows of
    // its neighbors.
    verticalScrollElasticity = .none
    contentView.postsBoundsChangedNotifications = true
  }

  /// The style of the scrollers, which the system sets when the user changes when scroll bars
  /// show, and once more shortly after the app starts, when it knows which pointing devices are
  /// connected.
  override var scrollerStyle: NSScroller.Style {
    didSet {
      guard scrollerStyle != oldValue else { return }
      // The scroller takes on its new style without the size and place of its knob, and takes
      // them only when they change: it would show the least knob at its end until the user
      // scrolls sideways. Changing both and back hands them over.
      if let scroller = horizontalScroller {
        let proportion = scroller.knobProportion
        let value = scroller.doubleValue
        scroller.knobProportion = proportion < 1 ? 1 : 0
        scroller.doubleValue = value < 1 ? 1 : 0
        scroller.knobProportion = proportion
        scroller.doubleValue = value
      }
      // A legacy scroller takes its height from the text, an overlay scroller lies above it.
      superview?.needsLayout = true
    }
  }

  /// Whether the scroll view is handling an event of the scroll wheel or the trackpad, during
  /// which its text moves because the user scrolls it by hand.
  private(set) var isHandlingScrollWheel = false

  override func scrollWheel(with event: NSEvent) {
    isHandlingScrollWheel = true
    defer { isHandlingScrollWheel = false }
    super.scrollWheel(with: event)
  }

  /// Scroll views of panes are never archived.
  required init?(coder: NSCoder) {
    nil
  }
}
