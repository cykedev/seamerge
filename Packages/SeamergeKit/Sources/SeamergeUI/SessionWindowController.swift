import AppKit
import MergeModel
import PaneKit

/// How a session window ended.
public enum SessionOutcome: Sendable {
  /// The result was saved.
  case saved

  /// The window closed without saving.
  case cancelled
}

/// The window of a merge: the three inputs side by side above, the result below.
@MainActor
public final class SessionWindowController: NSWindowController {
  /// Called exactly once, when the window closes for good, with how the session ended.
  public var onFinish: ((SessionOutcome) -> Void)?

  let layout: SessionSplitViewController
  private let sessionUndoManager: UndoManager
  private var hasFinished = false

  /// The accessibility settings the window draws with.
  var displayOptions: DisplayOptions {
    didSet {
      guard displayOptions != oldValue else { return }
      layout.apply(displayOptions.theme)
    }
  }

  /// Opens a window for `session`.
  ///
  /// - Parameters:
  ///   - session: A merge.
  ///   - undoManager: The undo manager of the window, which belongs to this session alone.
  /// - Precondition: `session` is a merge.
  public convenience init(session: Session, undoManager: UndoManager) {
    self.init(session: session, undoManager: undoManager, displayOptions: .current(in: .shared))
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(accessibilityDisplayOptionsDidChange(_:)),
      name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
  }

  /// Opens a window for `session` that draws with `displayOptions`, whatever the system's
  /// settings are.
  init(session: Session, undoManager: UndoManager, displayOptions: DisplayOptions) {
    precondition(session.kind == .merge, "A session window shows a merge")
    let layout = SessionSplitViewController(
      roles: Self.paneOrder.filter(session.roles.contains), theme: displayOptions.theme)
    self.layout = layout
    sessionUndoManager = undoManager
    self.displayOptions = displayOptions

    let window = NSWindow(
      contentRect: CGRect(origin: .zero, size: WindowMetrics.defaultContentSize),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered,
      defer: true)
    window.tabbingMode = .disallowed
    window.isReleasedWhenClosed = false
    super.init(window: window)
    // The delegate comes first: the window asks it for its undo manager once and keeps the
    // answer.
    window.delegate = self
    window.contentViewController = layout
    window.setContentSize(WindowMetrics.defaultContentSize)
    window.contentMinSize = CGSize(width: layout.minimumWidth, height: layout.minimumHeight)
    layout.updateMinimumWidths()
    layout.placeDividers()
  }

  /// The order of the panes above the result, from left to right.
  private static let paneOrder: [Role] = [.a, .base, .b]

  /// Session windows are never archived.
  public required init?(coder: NSCoder) {
    nil
  }

  @objc private func accessibilityDisplayOptionsDidChange(_ notification: Notification) {
    displayOptions = .current(in: .shared)
  }
}

extension SessionWindowController: NSWindowDelegate {
  /// The undo manager of the session, which no other window shares.
  public func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
    sessionUndoManager
  }

  /// Reports the end of the session, once.
  public func windowWillClose(_ notification: Notification) {
    guard !hasFinished else { return }
    hasFinished = true
    onFinish?(.cancelled)
  }
}
