import AppKit

/// The view that shows the find bar of a ``PaneSearch``: the standard find bar of AppKit, across
/// the full width of the view, as high as the bar while it shows and without height while it is
/// closed.
///
/// Put the view at the bottom of the window, below the panes, and lay it out at its intrinsic
/// height, which changes when the bar opens, closes or changes its height; the view has the
/// layout of its superview done again then.
public final class PaneFindBar: NSView, @MainActor NSTextFinderBarContainer {
  /// The search whose find bar the view shows.
  weak var search: PaneSearch?

  /// The find bar, which the finder of the search makes and assigns.
  public var findBarView: NSView? {
    didSet {
      guard findBarView !== oldValue else { return }
      oldValue?.removeFromSuperview()
      if let findBarView {
        addSubview(findBarView)
      }
      barDidChangeHeight()
    }
  }

  /// Whether the find bar shows, which the finder of the search sets.
  ///
  /// Closing the bar while it holds the focus hands the focus to the pane that the search
  /// started from.
  public var isFindBarVisible = false {
    didSet {
      guard isFindBarVisible != oldValue else { return }
      let hadFocus = !isFindBarVisible && holdsFocus
      findBarView?.isHidden = !isFindBarVisible
      barDidChangeHeight()
      if !isFindBarVisible {
        search?.findBarDidClose()
        if hadFocus {
          search?.findBarDidCloseWithFocus()
        }
      }
    }
  }

  /// Tells the view that the find bar changed its height, as it does when the user shows or
  /// hides the field for replacing.
  public func findBarViewDidChangeHeight() {
    barDidChangeHeight()
  }

  /// No content to dim: the tints of the panes carry meaning.
  public func contentView() -> NSView? {
    nil
  }

  public override var isFlipped: Bool { true }

  /// The height of the find bar while it shows, and no height otherwise.
  public override var intrinsicContentSize: NSSize {
    NSSize(width: NSView.noIntrinsicMetric, height: barHeight)
  }

  /// The height that the view takes now: the height of the find bar while it shows, else 0.
  public var barHeight: CGFloat {
    guard isFindBarVisible, let findBarView else { return 0 }
    return findBarView.frame.height
  }

  public override func layout() {
    super.layout()
    guard let findBarView else { return }
    findBarView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: findBarView.frame.height)
  }

  /// Whether the user types in the search field of the find bar, whose field editor holds the
  /// focus.
  var holdsSearchFocus: Bool {
    guard let findBarView, let field = (window?.firstResponder as? NSText)?.delegate as? NSView
    else { return false }
    return field is NSSearchField && field.isDescendant(of: findBarView)
  }

  /// Whether the focus lies in the find bar: in one of its fields, whose field editor holds it.
  private var holdsFocus: Bool {
    guard let findBarView, let responder = window?.firstResponder else { return false }
    let view = (responder as? NSText)?.delegate as? NSView ?? responder as? NSView
    return view?.isDescendant(of: findBarView) ?? false
  }

  private func barDidChangeHeight() {
    invalidateIntrinsicContentSize()
    needsLayout = true
    superview?.needsLayout = true
  }
}
