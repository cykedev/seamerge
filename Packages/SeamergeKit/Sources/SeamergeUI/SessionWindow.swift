import AppKit

/// The window of a session, which lets its controller see each key before the view with the
/// focus does, so that single keys act as commands in block mode, and tells it where the focus
/// goes.
class SessionWindow: NSWindow {
  /// Sees each key first and learns where the focus goes; the window does not retain it.
  weak var keyHandler: (any SessionKeyHandling)?

  /// Creates a window at the size of a new session window, with a title bar and the buttons to
  /// close, minimize and zoom it, that can be resized.
  convenience init() {
    self.init(
      contentRect: CGRect(origin: .zero, size: WindowMetrics.defaultContentSize),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered,
      defer: true)
  }

  override func sendEvent(_ event: NSEvent) {
    if event.type == .keyDown, keyHandler?.handleKeyDown(event) == true {
      return
    }
    super.sendEvent(event)
  }

  @discardableResult
  override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
    let made = super.makeFirstResponder(responder)
    if made {
      keyHandler?.windowDidChangeFirstResponder(self)
    }
    return made
  }
}

/// Sees the keys of a session window before the view with the focus does, and learns where the
/// focus goes.
@MainActor
protocol SessionKeyHandling: AnyObject {
  /// Handles `event`, a key going down, and tells whether it did, so that the view with the
  /// focus does not see it.
  func handleKeyDown(_ event: NSEvent) -> Bool

  /// Tells that another responder of `window` has the focus now.
  func windowDidChangeFirstResponder(_ window: NSWindow)
}
