import AppKit

/// The window of a session, which lets its controller see each key before the view with the
/// focus does, so that single keys act as commands in block mode, tells it where the focus
/// goes, and asks it whether Undo and Redo can act.
class SessionWindow: NSWindow {
  /// Sees each key first, learns where the focus goes and says whether Undo and Redo can act;
  /// the window does not retain it.
  weak var keyHandler: (any SessionKeyHandling)?

  override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
    if item.action == Self.undoAction, keyHandler?.allowsUndo == false {
      return false
    }
    if item.action == Self.redoAction, keyHandler?.allowsRedo == false {
      return false
    }
    return super.validateUserInterfaceItem(item)
  }

  /// The action of Undo, which the window carries out with its undo manager.
  private static let undoAction = Selector(("undo:"))

  /// The action of Redo, which the window carries out with its undo manager.
  private static let redoAction = Selector(("redo:"))

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

/// Sees the keys of a session window before the view with the focus does, learns where the
/// focus goes, and says whether Undo and Redo can act.
@MainActor
protocol SessionKeyHandling: AnyObject {
  /// Whether Undo can act now, as far as the undo manager has a step for it.
  var allowsUndo: Bool { get }

  /// Whether Redo can act now, as far as the undo manager has a step for it.
  var allowsRedo: Bool { get }

  /// Handles `event`, a key going down, and tells whether it did, so that the view with the
  /// focus does not see it.
  func handleKeyDown(_ event: NSEvent) -> Bool

  /// Tells that another responder of `window` has the focus now.
  func windowDidChangeFirstResponder(_ window: NSWindow)
}
