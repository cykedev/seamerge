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

  /// Where the result goes and what Git is doing.
  let context: SessionContext

  /// The pasteboard that Copy and Copy Path write to.
  let pasteboard: NSPasteboard

  /// The workspace that opens files and shows them in the Finder.
  let workspace: any Workspace
  private let summary: SessionSummary
  private let sessionUndoManager: UndoManager
  private var hasFinished = false

  /// The pane above the result that had the focus last, which gets it back when text mode ends.
  private(set) weak var lastSourcePane: PaneView?

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
      displayOptions: .current(in: .shared), pasteboard: .general, workspace: NSWorkspace.shared)
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(accessibilityDisplayOptionsDidChange(_:)),
      name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
  }

  /// Opens a window for `session` that draws with `displayOptions`, whatever the system's
  /// settings are, and copies to `pasteboard` and opens files with `workspace`.
  init(
    session: Session, context: SessionContext, undoManager: UndoManager,
    displayOptions: DisplayOptions, pasteboard: NSPasteboard, workspace: any Workspace
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
    self.context = context
    self.pasteboard = pasteboard
    self.workspace = workspace
    sessionUndoManager = undoManager
    self.displayOptions = displayOptions
    presentation = MergePresentation(
      session: session, layout: layout, headers: headers, resultHeader: resultHeader,
      displayOptions: displayOptions)
    summary = SessionSummary(changes: presentation.changes, context: context)

    let window = SessionWindow(
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
    presentation.delegate = self
    layout.delegate = self
    window.keyHandler = self
    if let first = layout.sourcePanes.first?.pane.documentView {
      window.initialFirstResponder = first
      window.makeFirstResponder(first)
    }
  }

  /// Remembers which pane above the result has the focus, which gets it back when text mode
  /// ends.
  func windowDidChangeFirstResponder(_ window: NSWindow) {
    let focused = layout.sourcePanes.first { window.firstResponder === $0.pane.documentView }
    if let focused {
      lastSourcePane = focused.pane
    }
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

extension SessionWindowController: NSUserInterfaceValidations {
  /// Whether the command of `item` can have an effect now.
  public func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
    guard let command = SessionCommand(action: item.action) else { return false }
    return canPerform(command)
  }

  /// Whether `command` can have an effect now.
  func canPerform(_ command: SessionCommand) -> Bool {
    switch command.requirement {
    case .jumpTarget(let jump):
      presentation.navigation.target(of: jump) != nil
    case .anotherPane:
      focusablePanes.count > 1
    case .blockText:
      !blockText(at: CopiedPlace(pane: focusedPane, block: presentation.currentBlock)).isEmpty
    }
  }
}

extension SessionWindowController: MergePresentationDelegate {
  func presentation(
    _ presentation: MergePresentation, menuFor hit: PaneHit, in pane: PaneView
  ) -> NSMenu {
    contextMenu(for: hit, in: pane)
  }
}

extension SessionWindowController: SessionLayoutDelegate {
  func layout(_ layout: SessionSplitViewController, menuForHeaderOf role: Role?) -> NSMenu? {
    headerMenu(for: role)
  }
}
