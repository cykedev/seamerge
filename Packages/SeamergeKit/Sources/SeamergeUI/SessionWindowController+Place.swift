import AppKit

/// Where a session window opens: where the last window of its kind closed, at its size and with
/// its split between the inputs and the result.
extension SessionWindowController {
  /// The kind of the window, each of which remembers its place apart.
  var windowKind: SessionWindowKind {
    if collection != nil { return .collection }
    return presentation.changes.session.kind == .merge ? .merge : .comparison
  }

  /// Puts the window where the last window of its kind closed, if one did, a step down from
  /// any session window that shows there already, and gives the inputs above the result the
  /// share of the height they had.
  func takeLastPlace() {
    guard let window else { return }
    if let frame = settings.windowFrame(of: windowKind) {
      window.setFrame(from: frame)
      let others = NSApplication.shared.windows.filter {
        $0 !== window && $0 is SessionWindow && $0.isVisible
      }
      var topLeft = CGPoint(x: window.frame.minX, y: window.frame.maxY)
      while others.contains(where: { $0.frame.origin == window.frame.origin }) {
        topLeft = window.cascadeTopLeft(from: topLeft)
        window.setFrameTopLeftPoint(topLeft)
      }
    }
    if let fraction = settings.sourcesFraction {
      layout.sourcesFraction = fraction
    }
  }

  /// Remembers where the window is, how large, and how the height is shared above the result,
  /// for the next window of its kind; a window in full screen leaves the place as it was.
  func rememberPlace() {
    guard let window, !window.styleMask.contains(.fullScreen) else { return }
    settings.setWindowFrame(window.frameDescriptor, of: windowKind)
    if let fraction = layout.currentSourcesFraction {
      settings.sourcesFraction = fraction
    }
  }
}
