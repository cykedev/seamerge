import AppKit

/// The pages of the window Settings in its toolbar, which give the window the size of the page
/// they turn to while they cross-fade, rather than once the cross-fade is over; with Reduce
/// Motion, the page and the size change at once.
///
/// The window keeps its top edge in place, as the window Settings of every app does.
final class SettingsTabViewController: NSTabViewController {
  /// Whether the pages cut rather than cross-fade.
  let reducesMotion: Bool

  /// Creates the pages, which cut if `reducesMotion` and cross-fade otherwise.
  init(reducesMotion: Bool) {
    self.reducesMotion = reducesMotion
    super.init(nibName: nil, bundle: nil)
    tabStyle = .toolbar
    transitionOptions = reducesMotion ? [] : [.crossfade, .allowUserInteraction]
  }

  /// Pages of Settings are never archived.
  required init?(coder: NSCoder) {
    nil
  }

  /// Turns from one page to the other as the tab view controller does, and sizes the window for
  /// the new page in the same moment.
  ///
  /// The page measures its size only once its view lies in the window, so the window takes the
  /// size after the page has come in; the tab view controller then finds the window at the size
  /// it would give it after the cross-fade, and leaves it.
  override func transition(
    from fromViewController: NSViewController, to toViewController: NSViewController,
    options: NSViewController.TransitionOptions = [],
    completionHandler completion: (@Sendable () -> Void)? = nil
  ) {
    super.transition(
      from: fromViewController, to: toViewController, options: options,
      completionHandler: completion)
    guard let window = view.window else { return }
    toViewController.view.layoutSubtreeIfNeeded()
    let frame = Self.frame(of: window, fitting: toViewController.preferredContentSize)
    guard frame != window.frame else { return }
    if reducesMotion {
      window.setFrame(frame, display: true)
    } else {
      NSAnimationContext.runAnimationGroup { _ in
        window.animator().setFrame(frame, display: true)
      }
    }
  }

  /// The frame of `window` with content of `size`, rounded up to whole points as the window
  /// rounds it, and its top edge where it is.
  private static func frame(of window: NSWindow, fitting size: CGSize) -> CGRect {
    // The title bar and the toolbar, as the window lays out its content.
    let content = window.contentRect(forFrameRect: window.frame).size
    let width = (window.frame.width - content.width + size.width).rounded(.up)
    let height = (window.frame.height - content.height + size.height).rounded(.up)
    return CGRect(
      x: window.frame.minX, y: window.frame.maxY - height, width: width, height: height)
  }
}
