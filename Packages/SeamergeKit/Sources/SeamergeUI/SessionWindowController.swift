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

/// The window of a merge: the three inputs side by side above, the result below, and a title
/// that names the file and sums up the changes.
@MainActor
public final class SessionWindowController: NSWindowController {
  /// Called exactly once, when the window closes for good, with how the session ended.
  public var onFinish: ((SessionOutcome) -> Void)?

  let layout: SessionSplitViewController
  let presentation: MergePresentation
  private let summary: SessionSummary
  private let sessionUndoManager: UndoManager
  private var hasFinished = false

  /// The accessibility settings the window draws with.
  var displayOptions: DisplayOptions {
    didSet {
      guard displayOptions != oldValue else { return }
      let theme = displayOptions.theme
      layout.apply(theme)
      presentation.apply(theme)
      presentation.displayOptions = displayOptions
    }
  }

  /// Opens a window for `session`.
  ///
  /// The window shows the merge as loaded: every conflict open, every other change taken as the
  /// merge takes it.
  ///
  /// - Parameters:
  ///   - session: A merge.
  ///   - context: Where the result goes and what Git is doing.
  ///   - undoManager: The undo manager of the window, which belongs to this session alone.
  /// - Precondition: `session` is a merge.
  public convenience init(
    session: Session, context: SessionContext = SessionContext(), undoManager: UndoManager
  ) {
    self.init(
      session: session, context: context, undoManager: undoManager,
      displayOptions: .current(in: .shared))
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(accessibilityDisplayOptionsDidChange(_:)),
      name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
  }

  /// Opens a window for `session` that draws with `displayOptions`, whatever the system's
  /// settings are.
  init(
    session: Session, context: SessionContext, undoManager: UndoManager,
    displayOptions: DisplayOptions
  ) {
    precondition(session.kind == .merge, "A session window shows a merge")
    let theme = displayOptions.theme
    let headers = Dictionary(
      uniqueKeysWithValues: Self.paneOrder.filter(session.roles.contains).map { role in
        (role, SideHeader(role: role, session: session, context: context))
      })
    let resultHeader = ResultHeader(session: session, context: context)
    let layout = SessionSplitViewController(
      headers: Self.paneOrder.compactMap { headers[$0] }, resultHeader: resultHeader, theme: theme)
    self.layout = layout
    sessionUndoManager = undoManager
    self.displayOptions = displayOptions
    presentation = MergePresentation(
      session: session, layout: layout, headers: headers, resultHeader: resultHeader,
      displayOptions: displayOptions)
    summary = SessionSummary(changes: presentation.changes, context: context)

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
    window.title = summary.title
    window.representedURL = context.resultURL
    window.setAccessibilityTitle([summary.title, summary.fullSubtitle].joined(separator: ", "))
    layout.updateMinimumWidths()
    layout.placeDividers()
    updateSubtitle()
    presentation.showCurrentBlock()
  }

  /// The order of the panes above the result, from left to right.
  private static let paneOrder: [Role] = [.a, .base, .b]

  /// Session windows are never archived.
  public required init?(coder: NSCoder) {
    nil
  }

  /// Tells the window that the Git command that asked for the merge no longer waits, so that it
  /// says so below the result header.
  public func callerDisconnected() {
    layout.showCallerIsGone()
  }

  /// Shows as much of the subtitle as the width of the window allows; the rest stays in the
  /// title that VoiceOver reads.
  private func updateSubtitle() {
    guard let window else { return }
    let titleWidth = (window.title as NSString).size(withAttributes: [
      .font: NSFont.titleBarFont(ofSize: 0)
    ]).width
    let width = window.frame.width - 2 * WindowMetrics.titlebarControlsWidth - titleWidth
    window.subtitle = summary.subtitle(
      fittingWidth: width, font: .preferredFont(forTextStyle: .subheadline))
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

  /// Fits the subtitle to the new width.
  public func windowDidResize(_ notification: Notification) {
    updateSubtitle()
  }

  /// Reports the end of the session, once.
  public func windowWillClose(_ notification: Notification) {
    guard !hasFinished else { return }
    hasFinished = true
    onFinish?(.cancelled)
  }
}
