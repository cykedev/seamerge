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

/// The window of a merge: the three inputs side by side above, the result below, a title that
/// names the file and sums up the changes, and a toolbar with the open conflicts.
///
/// The controller carries out the commands of the window, ``SessionCommand``, which reach it
/// along the responder chain from the main menu, the context menus, the toolbar and the single
/// keys of block mode, and validates them.
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

  /// What the window asks or tells while it switches to another comparison.
  let prompts: any ComparisonPrompts

  /// The undo manager of the window, which belongs to this session alone.
  let sessionUndoManager: UndoManager

  private var summary: SessionSummary
  private var hasFinished = false

  /// Whether the files are being compared anew.
  var isSwitchingComparison = false

  /// Whether the toolbar says that the files are being compared anew, which it does once the
  /// comparison has taken a moment.
  var showsComparisonProgress = false

  /// The toolbar of the window.
  let toolbar: SessionToolbar

  /// The pane above the result that had the focus last, which gets it back when text mode ends.
  private(set) weak var lastSourcePane: PaneView?

  /// The accessibility settings the window draws with.
  var displayOptions: DisplayOptions {
    didSet {
      guard displayOptions != oldValue else { return }
      presentation.displayOptions = displayOptions
      applyTheme()
    }
  }

  /// The size of the code, in points.
  var fontSize = SessionWindowController.standardFontSize {
    didSet {
      guard fontSize != oldValue else { return }
      presentation.keepingTheLineOfBInPlace { applyTheme() }
      updateMinimumSize()
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
      displayOptions: .current(in: .shared), pasteboard: .general, workspace: NSWorkspace.shared,
      prompts: ComparisonSheets(), doneStyle: .standard, window: SessionWindow())
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(accessibilityDisplayOptionsDidChange(_:)),
      name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
  }

  /// Opens a window for `session` that draws with `displayOptions`, whatever the system's
  /// settings are, copies to `pasteboard`, opens files with `workspace`, asks with `prompts`,
  /// shows the button that saves and closes in `doneStyle`, and lays itself out in `window`.
  init(
    session: Session, context: SessionContext, undoManager: UndoManager,
    displayOptions: DisplayOptions, pasteboard: NSPasteboard, workspace: any Workspace,
    prompts: any ComparisonPrompts, doneStyle: SessionToolbar.DoneStyle, window: SessionWindow
  ) {
    precondition(session.kind == .merge, "A session window shows a merge")
    let theme = displayOptions.theme(fontSize: Self.standardFontSize)
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
    self.prompts = prompts
    toolbar = SessionToolbar(doneStyle: doneStyle)
    sessionUndoManager = undoManager
    self.displayOptions = displayOptions
    presentation = MergePresentation(
      session: session, layout: layout, headers: headers, resultHeader: resultHeader,
      displayOptions: displayOptions)
    summary = SessionSummary(changes: presentation.changes, context: context)

    window.tabbingMode = .disallowed
    window.isReleasedWhenClosed = false
    window.toolbarStyle = .unified
    super.init(window: window)
    // The delegate comes first: the window asks it for its undo manager once and keeps the
    // answer.
    window.delegate = self
    window.contentViewController = layout
    window.toolbar = toolbar.toolbar
    window.setContentSize(WindowMetrics.defaultContentSize)
    window.contentMinSize = CGSize(width: layout.minimumWidth, height: layout.minimumHeight)
    window.title = summary.title
    window.representedURL = context.resultURL
    layout.updateMinimumWidths()
    layout.placeDividers()
    sessionDidChange()
    presentation.showCurrentBlock()
    presentation.delegate = self
    layout.delegate = self
    window.keyHandler = self
    if let first = layout.sourcePanes.first?.pane.documentView {
      window.initialFirstResponder = first
      window.makeFirstResponder(first)
    }
    stateDidChange()
  }

  /// Shows in the toolbar what changed: the open conflicts, the arrows that lead anywhere, a
  /// comparison under way, and whether the window can save and close.
  func stateDidChange() {
    let navigation = presentation.navigation
    toolbar.update(
      openConflictCount: navigation.openConflictCount,
      hasConflicts: presentation.changes.blocks.contains { $0.kind == .conflict },
      isComparing: showsComparisonProgress, isValid: canPerform,
      canSaveAndClose: responds(along: SessionToolbar.saveAndClose))
    updateSubtitle()
  }

  /// Whether a responder of the window, from the view with the focus to the application,
  /// carries out `action`.
  private func responds(along action: Selector) -> Bool {
    var responders: [NSResponder] = []
    var responder = window?.firstResponder
    while let next = responder {
      responders.append(next)
      responder = next.nextResponder
    }
    responder = self
    while let next = responder {
      responders.append(next)
      responder = next.nextResponder
    }
    let application = NSApplication.shared
    return responders.contains { $0.responds(to: action) } || application.responds(to: action)
      || (application.delegate as? NSObject)?.responds(to: action) == true
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

  /// Draws the window with the theme of its display options and font size.
  private func applyTheme() {
    let theme = displayOptions.theme(fontSize: fontSize)
    layout.apply(theme)
    presentation.apply(theme)
  }

  /// Titles the window after the session it shows now.
  func sessionDidChange() {
    summary = SessionSummary(changes: presentation.changes, context: context)
    window?.setAccessibilityTitle([summary.title, summary.fullSubtitle].joined(separator: ", "))
    updateSubtitle()
  }

  /// Shows as much of the subtitle as the room before the number of open conflicts in the
  /// toolbar allows; the rest stays in the title that VoiceOver reads.
  ///
  /// The subtitle stands below the title, after the buttons of the window. Until the toolbar is
  /// laid out, its middle stands for the start of the number.
  private func updateSubtitle() {
    guard let window else { return }
    let end = toolbar.conflictCountMinX ?? window.frame.width / 2
    let width = end - WindowMetrics.titlebarControlsWidth - WindowMetrics.toolbarSpacing
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
  ///
  /// A menu item of a comparison mode, and Synchronize Scrolling, show a checkmark while they
  /// are in effect; a command that switches something on and off takes the name that says what
  /// it does now, such as Show Base while the base is hidden.
  public func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
    guard let command = SessionCommand(action: item.action) else { return false }
    if let menuItem = item as? NSMenuItem {
      if let mode = command.comparisonMode {
        menuItem.state = mode == comparisonOptions.mode ? .on : .off
      } else if command == .toggleScrollSynchronization {
        menuItem.state = presentation.scrollSync.isEnabled ? .on : .off
      }
      if let alternateTitle = command.alternateTitle {
        menuItem.title = isSwitchedOn(command) ? alternateTitle : command.title
      }
    }
    return canPerform(command)
  }

  /// Whether what `command` switches is on: the base hidden, the result maximized, the
  /// invisible characters shown, all lines shown.
  func isSwitchedOn(_ command: SessionCommand) -> Bool {
    switch command {
    case .toggleBase: !layout.showsBase
    case .toggleResultMaximized: layout.maximizesResult
    case .toggleInvisibles: layout.resultPane.showsInvisibles
    case .toggleCollapsedLines: !presentation.collapsesUnchangedRows
    case .toggleScrollSynchronization: presentation.scrollSync.isEnabled
    default: false
    }
  }

  /// Whether `command` can have an effect now.
  func canPerform(_ command: SessionCommand) -> Bool {
    switch command.requirement {
    case .jumpTarget(let jump):
      presentation.navigation.target(of: jump) != nil
    case .anotherPane:
      focusablePanes.count > 1
    case .noComparisonUnderWay:
      !isSwitchingComparison
    case .basePane:
      presentation.changes.hasBase && !layout.maximizesResult
    case .collapsibleRows:
      presentation.canToggleCollapsedRows(caretLine: caretLineInTextMode)
    case .largerFontSize:
      fontSize < Self.fontSizes[Self.fontSizes.count - 1]
    case .smallerFontSize:
      fontSize > Self.fontSizes[0]
    case .otherFontSize:
      fontSize != Self.standardFontSize
    case .fileOnDisk:
      editableFileURL != nil
    case .blockText:
      !blockText(at: CopiedPlace(pane: focusedPane, block: presentation.currentBlock)).isEmpty
    case .nothing:
      true
    }
  }
}

extension SessionWindowController: MergePresentationDelegate {
  func presentationDidChangeCurrentBlock(_ presentation: MergePresentation) {
    stateDidChange()
  }

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
