public import AppKit
public import FolderCompare
public import MergeModel
import PaneKit
import SyntaxKit

/// How a session window ended, which the Git command that waits for it takes as success or
/// failure.
public enum SessionOutcome: Sendable {
  /// The result of a merge was saved, or a comparison was closed after it was seen.
  case saved

  /// A merge closed without saving, or a comparison was closed with the files after it skipped.
  case cancelled
}

/// The window of a session: the inputs side by side, a title that names the file and sums up the
/// changes, and a toolbar that counts the open conflicts or the changes.
///
/// One window shows both kinds of session, put together from the same parts. A merge shows A,
/// Base and B above its result, with the decision column beside it. A comparison of two files
/// shows the older file on the left and the newer one on the right, both read-only, and nothing
/// below them.
///
/// The controller carries out the commands of the window, ``SessionCommand``, which reach it
/// along the responder chain from the main menu, the context menus, the toolbar and the single
/// keys of block mode, and validates them.
@MainActor
public final class SessionWindowController: NSWindowController {
  /// Called exactly once, when the window closes for good, with how the session ended.
  public var onFinish: ((SessionOutcome) -> Void)?

  let layout: SessionSplitViewController
  let presentation: SessionPresentation

  /// The panes and the footer below them.
  let content: SessionContentController

  /// The settings of the app: how the code is drawn, and how the window starts.
  let settings: UserSettings

  /// Whether the window colors its code by its syntax.
  var highlightsSyntax: Bool

  /// The language of the files as the window recognized it.
  var detectedLanguage: LanguageDescription

  /// The languages chosen for files, by their paths, while the app runs.
  let syntaxChoices: SyntaxChoices

  /// The path of the file whose language the window recognized, under which it keeps the
  /// language chosen for it.
  var syntaxPath: String

  /// Where the result goes, what Git is doing, and who waits for the session; in a window that
  /// compares several files, what Git says about the file it shows.
  public internal(set) var context: SessionContext

  /// The pasteboard that Copy and Copy Path write to.
  let pasteboard: NSPasteboard

  /// The workspace that opens files and shows them in the Finder.
  let workspace: any Workspace

  /// What the window asks or tells while it switches to another comparison.
  let prompts: any SessionPrompts

  /// The undo manager of the window, which belongs to this session alone.
  let sessionUndoManager: UndoManager

  private var summary: SessionSummary

  /// Whether the window has reported how the session ended.
  private(set) var hasFinished = false

  /// What the window knows about the file of the result of a merge; `nil` for a comparison.
  var saving: ResultSaving?

  /// Whether the window is asking whether to save before it closes.
  var isAskingToClose = false

  /// The watch of the files of the session and of the result on disk, which has the window
  /// reload them once they change.
  let diskWatch = DiskWatch()

  /// Whether the window is saving its result, which a reload waits for.
  var isSaving = false

  /// The sheet of Change Files while it is open.
  var changeFilesSheet: CompareFilesWindowController?

  /// What the window shows of the lines of its files: the lines, the headers of the files above
  /// empty panes while it waits for the lines, or why it shows none.
  var phase = SessionPhase.ready

  /// Which file of its collection a window that compares several files shows, and what it has
  /// read of them; `nil` for a window of one session.
  let collectionNavigator: CollectionNavigator?

  /// The files of a window that compares several, or `nil` for a window of one session.
  public var collection: FileCollection? {
    collectionNavigator?.collection
  }

  /// The sidebar with the list of the files and the panes beside it, if the window compares
  /// several files.
  let collectionLayout: CollectionSplitViewController?

  /// The reading of the file the window is about to show, while it runs.
  var fileLoad: Task<Void, Never>?

  /// How long the window waits for another file of its collection to be ready before it shows
  /// the headers of the file above empty panes meanwhile, in seconds; for none, it shows them at
  /// once.
  var fileWait = SessionWindowController.comparisonWait

  /// The merge of a file that is not text, whose window asks which side to take, or `nil`.
  let binaryMerge: BinaryMerge?

  /// The comparison of the files anew, one at a time, and the return to an earlier one that undo
  /// or redo brings back.
  let comparisonSwitcher: ComparisonSwitcher

  /// Whether a comparison of two files leaves out the text that the ignore rules of Settings
  /// match; every window starts with it, since whoever writes rules wants them.
  var usesIgnoreRules = true

  /// Whether the comparison of two files in view has a patch, worked out once for each
  /// comparison shown rather than whenever a menu asks, since it compares the files byte for
  /// byte.
  var comparisonHasPatch = false

  /// Whether the toolbar says that the files are being compared anew, which it does once the
  /// comparison has taken a moment.
  var showsComparisonProgress = false

  /// The toolbar of the window.
  let toolbar: SessionToolbar

  /// Which files of the comparison shown may be written by copying changes, decided as the
  /// window first shows them; `nil` before, and where a file was not read from disk.
  var writableSides: WritableSides?

  /// The locations of the files that ``writableSides`` was decided for.
  var writableFileURLs: [URL?] = []

  /// The bytes of the files of the comparisons on disk, as far as the window knows them, which
  /// tell the files whose copied changes are not saved.
  var filesOnDisk = FilesOnDisk()

  /// The roles of the files of the comparison shown whose copied changes are not saved.
  var editedRoles: Set<Role> = []

  /// Whether the panes stand empty below the headers of a file of the collection, which the
  /// window shows while it waits for the lines of the file; its files count as unchanged then.
  var showsHeadersOnly = false

  /// The last copy of changes that a command or a button began, which ends once the window
  /// shows its outcome.
  var copying: Task<Void, Never>?

  /// The pane above the result that had the focus last, which gets it back when text mode ends.
  private(set) weak var lastSourcePane: PaneView?

  /// The steps of undo of the result, among them the runs of typing.
  let resultUndo: ResultUndo

  /// The accessibility settings the window draws with.
  var displayOptions: DisplayOptions {
    didSet {
      guard displayOptions != oldValue else { return }
      presentation.displayOptions = displayOptions
      applyTheme()
    }
  }

  /// The size of the code in the settings when the window last took it over, which tells a
  /// change of the size from a change of the font.
  var settingsFontSize: CGFloat

  /// The size of the code, in points: the size of the settings until the user zooms.
  var fontSize: CGFloat {
    didSet {
      guard fontSize != oldValue else { return }
      presentation.keepingTheLineOfBInPlace { applyTheme() }
      updateMinimumSize()
    }
  }

  /// Opens a window for `session`.
  ///
  /// The window shows a merge as loaded: every conflict open, every other change taken as the
  /// merge takes it.
  ///
  /// - Parameters:
  ///   - session: A merge or a comparison of two files.
  ///   - context: Where the result goes and what Git is doing.
  ///   - undoManager: The undo manager of the window, which belongs to this session alone.
  ///   - settings: How the code is drawn and how the window starts.
  public convenience init(
    session: Session, context: SessionContext = SessionContext(), undoManager: UndoManager,
    settings: UserSettings
  ) {
    self.init(
      session: session, context: context, undoManager: undoManager,
      displayOptions: .current(in: .shared), pasteboard: .general, workspace: NSWorkspace.shared,
      prompts: SessionSheets(), doneStyle: .standard, settings: settings, syntaxChoices: .shared,
      window: SessionWindow())
    observeDisplayOptions()
  }

  /// Opens a window for `comparison`, whose files cannot be compared.
  ///
  /// The window names the files in its headers and says why in place of their lines; every
  /// command but Skip Remaining Files is invalid. Closing it lets Git go on to the next file, as
  /// for any comparison.
  ///
  /// - Throws: ``SessionLoadingError/comparisonFailed`` if not even the headers can be made.
  public convenience init(
    unavailable comparison: UnavailableComparison, context: SessionContext,
    undoManager: UndoManager, settings: UserSettings
  ) async throws(SessionLoadingError) {
    let session = try await comparison.emptySession()
    self.init(
      session: session, context: context, undoManager: undoManager,
      displayOptions: .current(in: .shared), pasteboard: .general, workspace: NSWorkspace.shared,
      prompts: SessionSheets(), doneStyle: .standard, settings: settings, syntaxChoices: .shared,
      window: SessionWindow(), unavailable: comparison)
    observeDisplayOptions()
  }

  /// Opens a window for `merge`, whose files are not text: it names the sides in its headers,
  /// says why it shows no lines, and asks in a sheet which side to take as a whole, once it
  /// shows.
  ///
  /// - Throws: ``SessionLoadingError/comparisonFailed`` if not even the headers can be made.
  public convenience init(
    binaryMerge merge: BinaryMerge, context: SessionContext, undoManager: UndoManager,
    settings: UserSettings
  ) async throws(SessionLoadingError) {
    let session = try await merge.emptySession()
    self.init(
      session: session, context: context, undoManager: undoManager,
      displayOptions: .current(in: .shared), pasteboard: .general, workspace: NSWorkspace.shared,
      prompts: SessionSheets(), doneStyle: .standard, settings: settings, syntaxChoices: .shared,
      window: SessionWindow(), binaryMerge: merge)
    observeDisplayOptions()
  }

  /// Draws anew whenever the accessibility settings of the system change.
  func observeDisplayOptions() {
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(accessibilityDisplayOptionsDidChange(_:)),
      name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
  }

  /// Opens a window for `session` that draws with `displayOptions`, whatever the system's
  /// settings are, copies to `pasteboard`, opens files with `workspace`, asks with `prompts`,
  /// shows the button that saves and closes of a merge in `doneStyle`, draws and starts as
  /// `settings` say, keeps the languages chosen for files in `syntaxChoices`, and lays itself
  /// out in `window`; for an `unavailable` comparison, it says why in place of the lines. `now`
  /// tells the time, which ends a run of typing after a pause.
  ///
  /// With a `pendingComparison`, `session` names the files without their lines, and the window
  /// shows their headers and empty panes until the comparison is ready, then the session it
  /// makes.
  ///
  /// For a `collection`, the window shows `session`, one of its files, beside the list of the
  /// files; with a `pendingFile`, `session` names that file without its lines, and the window
  /// waits for its comparison as for a `pendingComparison`.
  init(
    session: Session, context: SessionContext, undoManager: UndoManager,
    displayOptions: DisplayOptions, pasteboard: NSPasteboard, workspace: any Workspace,
    prompts: any SessionPrompts, doneStyle: SessionToolbar.DoneStyle, settings: UserSettings,
    syntaxChoices: SyntaxChoices = SyntaxChoices(),
    window: SessionWindow, unavailable: UnavailableComparison? = nil,
    binaryMerge: BinaryMerge? = nil, collection: FileCollection? = nil,
    pendingComparison: PendingComparison? = nil, pendingFile: PendingFile? = nil,
    now: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now }
  ) {
    let theme = displayOptions.theme(settings: settings, fontSize: settings.fontSize)
    let arrangement = PaneArrangement(session: session)
    let headers = SideHeader.headers(of: session, context: context)
    let resultHeader =
      arrangement.showsResult ? ResultHeader(session: session, context: context) : nil
    let layout = SessionSplitViewController(
      headers: arrangement.sourceRoles.compactMap { headers[$0] }, resultHeader: resultHeader,
      theme: theme)
    self.layout = layout
    let search = PaneSearch()
    let content = SessionContentController(
      layout: layout, findBar: search.findBar,
      footer: SessionFooterView(
        toggles: FooterToggle.allCases.filter {
          $0 != .base || arrangement.sourceRoles.contains(.base)
        }))
    self.content = content
    content.footer.theme = theme
    self.settings = settings
    highlightsSyntax = settings.highlightsSyntax
    fontSize = settings.fontSize
    settingsFontSize = settings.fontSize
    self.syntaxChoices = syntaxChoices
    let detectedLanguage = SessionSyntax.language(of: session, resultURL: context.resultURL)
    self.detectedLanguage = detectedLanguage
    syntaxPath = SessionSyntax.path(of: session, resultURL: context.resultURL)
    self.context = context
    self.pasteboard = pasteboard
    self.workspace = workspace
    self.prompts = prompts
    toolbar = SessionToolbar(
      kind: session.kind, doneStyle: doneStyle, hasSidebar: collection != nil)
    collectionNavigator = collection.map {
      CollectionNavigator(collection: $0, showsIdenticalFiles: settings.showsIdenticalFiles)
    }
    collectionLayout = collection.map { _ in
      CollectionSplitViewController(
        fileList: FileListViewController(
          theme: theme, folderColor: CompareFilesColors(displayOptions).quietText),
        content: content, settings: settings)
    }
    sessionUndoManager = undoManager
    self.displayOptions = displayOptions
    presentation = SessionPresentation(
      session: session, arrangement: arrangement, layout: layout, headers: headers,
      resultHeader: resultHeader, displayOptions: displayOptions,
      language: settings.highlightsSyntax
        ? syntaxChoices[syntaxPath].language(detected: detectedLanguage) : nil,
      alignsLines: settings.alignsLines, search: search)
    let resultUndo = ResultUndo(undoManager: undoManager, presentation: presentation, now: now)
    self.resultUndo = resultUndo
    comparisonSwitcher = ComparisonSwitcher(
      undoManager: undoManager, presentation: presentation, resultUndo: resultUndo)
    presentation.wrapsLines = settings.wrapsLines
    for pane in presentation.allPanes {
      pane.showsInvisibles = settings.showsInvisibles
    }
    summary = SessionSummary(
      changes: presentation.changes, context: context, arrangement: arrangement,
      startMode: settings.comparisonMode, ignoredDifferences: presentation.ignoredDifferences)
    // A result comes with the comparison the window waits for.
    saving =
      pendingComparison == nil
      ? presentation.result.map {
        ResultSaving(result: $0, session: session, url: context.resultURL)
      } : nil
    phase = unavailable.map(SessionPhase.unavailable) ?? .ready
    self.binaryMerge = binaryMerge
    if let unavailable {
      layout.showInPlaceOfTheLines(
        UnavailableComparisonView(
          title: unavailable.title,
          message: unavailable.message(in: collection == nil ? context : SessionContext())))
    } else if let binaryMerge {
      layout.showInPlaceOfTheLines(
        UnavailableComparisonView(
          title: binaryMerge.title, message: BinaryMerge.message))
    }

    window.tabbingMode = .disallowed
    window.isReleasedWhenClosed = false
    window.toolbarStyle = .unified
    if collection != nil {
      // The sidebar reaches up under the toolbar.
      window.styleMask.insert(.fullSizeContentView)
    }
    super.init(window: window)
    diskWatch.delegate = self
    comparisonSwitcher.delegate = self
    // The delegate comes first: the window asks it for its undo manager once and keeps the
    // answer.
    window.delegate = self
    window.contentViewController = collectionLayout ?? content
    content.showsFooter = settings.showsFooter
    window.toolbar = toolbar.toolbar
    toolbar.insertArrangementOnce(rememberingIn: settings)
    window.setContentSize(WindowMetrics.defaultContentSize)
    window.contentMinSize = minimumContentSize
    window.title = summary.title
    window.representedURL = context.resultURL
    layout.updateMinimumWidths()
    takeLastPlace()
    layout.placeDividers()
    if arrangement.sourceRoles.contains(.base), !settings.showsBase {
      layout.showsBase = false
      presentation.showSourcesAgain()
    }
    if settings.showsSingleColumn, presentation.canShowSingleColumn {
      presentation.setShowsSingleColumn(true)
      updateMinimumSize()
    }
    sessionDidChange()
    presentation.showCurrentBlock()
    presentation.delegate = self
    layout.delegate = self
    layout.seamDelegate = self
    layout.chooseResultFormat = { [weak self] choice in self?.choose(choice) }
    window.keyHandler = self
    if unavailable == nil, binaryMerge == nil, let first = presentation.leadingPane?.documentView {
      window.initialFirstResponder = first
      window.makeFirstResponder(first)
    }
    observeFooterVisibility()
    observeTextSettings()
    observeIgnoreRules()
    setUpCollection(comparingFirstFile: pendingFile)
    if let pendingComparison {
      wait(for: pendingComparison)
    }
    stateDidChange()
    watchFiles()
  }

  /// Shows in the toolbar what changed: the open conflicts or the current change, the arrows
  /// that lead anywhere, a comparison under way, and whether the window can save and close.
  func stateDidChange() {
    updateCopyControls()
    toolbar.update(
      count: toolbarCount, isComparing: showsComparisonProgress,
      lineArrangement: presentation.lineArrangement, canShow: canShow, isValid: canPerform)
    window?.isDocumentEdited = hasUnsavedChanges
    updateFooter()
    updateSubtitle()
  }

  /// What the toolbar counts: the open conflicts of a merge, or the current change of a
  /// comparison, which has no conflicts.
  var toolbarCount: SessionToolbar.Count {
    switch phase {
    case .loading: return .waiting
    case .unavailable, .placeholder: return .nothing
    case .ready: break
    }
    let changes = presentation.changes
    switch changes.session.kind {
    case .merge:
      return .conflicts(
        open: presentation.navigation.openConflictCount,
        hadAny: changes.blocks.contains { $0.kind == .conflict })
    case .diff where binaryMerge != nil:
      return .nothing
    case .diff:
      return .changes(current: presentation.currentBlock, total: changes.blocks.count)
    }
  }

  /// Whether Undo can act now on the step it would take back.
  var allowsUndo: Bool {
    allowsStep(
      bringingBackAComparison:
        sessionUndoManager.undoActionUserInfoValue(forKey: ComparisonSwitcher.bringsBackComparison)
        != nil)
  }

  /// Whether Redo can act now on the step it would carry out again.
  var allowsRedo: Bool {
    allowsStep(
      bringingBackAComparison:
        sessionUndoManager.redoActionUserInfoValue(forKey: ComparisonSwitcher.bringsBackComparison)
        != nil)
  }

  /// Remembers which pane above the result has the focus, which gets it back when text mode
  /// ends.
  func windowDidChangeFirstResponder(_ window: NSWindow) {
    let focused = presentation.allPanes.first {
      $0 !== layout.resultPane && window.firstResponder === $0.documentView
    }
    if let focused {
      lastSourcePane = focused
    }
    presentation.updateResultExpandedRuns()
  }

  /// Session windows are never archived.
  public required init?(coder: NSCoder) {
    nil
  }

  /// Tells the window that the Git command that asked for the session no longer waits, so that a
  /// merge says so below the result header.
  public func callerDisconnected() {
    layout.showCallerIsGone()
  }

  /// Draws the window with the theme of its display options, settings and font size.
  func applyTheme() {
    let theme = displayOptions.theme(settings: settings, fontSize: fontSize)
    layout.apply(theme)
    presentation.apply(theme)
    content.footer.theme = theme
  }

  /// Titles the window after the session it shows now.
  func sessionDidChange() {
    updateEditedFiles()
    comparisonHasPatch = shownComparisonHasPatch
    summary = SessionSummary(
      changes: presentation.changes, context: context, arrangement: presentation.arrangement,
      startMode: settings.comparisonMode, ignoredDifferences: presentation.ignoredDifferences,
      isComparing: waitsForComparison)
    window?.title = summary.title
    window?.setAccessibilityTitle([summary.title, summary.fullSubtitle].joined(separator: ", "))
    updateSubtitle()
  }

  /// Shows as much of the subtitle as the room before the count in the middle of the toolbar
  /// allows; the rest stays in the title that VoiceOver reads.
  ///
  /// The subtitle stands below the title, after the buttons of the window. Until the toolbar is
  /// laid out, its middle stands for the start of the number.
  private func updateSubtitle() {
    guard let window else { return }
    let end = toolbar.countMinX ?? window.frame.width / 2
    let width = end - WindowMetrics.titlebarControlsWidth - WindowMetrics.toolbarSpacing
    window.subtitle = summary.subtitle(
      fittingWidth: width, font: .preferredFont(forTextStyle: .subheadline))
  }

  @objc private func accessibilityDisplayOptionsDidChange(_ notification: Notification) {
    displayOptions = .current(in: .shared)
  }
}

extension SessionWindowController: NSWindowDelegate {
  /// Reads the settings of the system again, among them Keyboard Navigation, which tells no
  /// one when it changes; the user changes it in another window.
  public func windowDidBecomeKey(_ notification: Notification) {
    displayOptions = .current(in: .shared)
  }

  /// The undo manager of the session, which no other window shares.
  public func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
    sessionUndoManager
  }

  /// Fits the subtitle to the new width.
  public func windowDidResize(_ notification: Notification) {
    updateSubtitle()
  }

  /// Asks whether to save first while the result of a merge or a file of a comparison has
  /// unsaved changes, and closes once the answer allows it.
  public func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard hasUnsavedChanges, !hasFinished else { return true }
    Task { await closeAskingFirst() }
    return false
  }

  /// Ends the search, remembers the place of the window for the next of its kind and reports
  /// the end of the session, once: a merge counts as saved if what the window shows was written
  /// to its file, and closing a comparison means it was seen, so that Git goes on to the next
  /// file.
  public func windowWillClose(_ notification: Notification) {
    comparisonSwitcher.stopBringingBack()
    fileLoad?.cancel()
    presentation.search.close()
    // The steps of undo keep the comparisons they bring back. The find bar's field editor may
    // keep the undo manager of the window once it has closed; without its steps, it is small.
    sessionUndoManager.removeAllActions()
    rememberPlace()
    diskWatch.stop()
    // A merge without a result yet, as while the window waits for it, was not saved.
    let isSaved =
      binaryMerge == nil
      && (saving.map { $0.url != nil && $0.saved != nil && !isResultEdited }
        ?? (presentation.changes.session.kind == .diff))
    finish(isSaved ? .saved : .cancelled)
  }
}

extension SessionWindowController {
  /// Closes a comparison that `git difftool` started and tells Git to compare no further files,
  /// after asking whether to save the files with copied changes first.
  @objc func skipRemainingFiles(_ sender: Any?) {
    guard canPerform(.skipRemainingFiles) else { return }
    guard hasChangedFiles else {
      cancel()
      return
    }
    Task { await skipRemainingFilesAskingFirst() }
  }

  /// Closes the window and tells Git to compare no further files, once files with copied
  /// changes are saved or the user lets them go; tells whether it closed.
  @discardableResult
  func skipRemainingFilesAskingFirst() async -> Bool {
    guard await saveChangedFilesAskingFirst() else { return false }
    cancel()
    return true
  }

  /// Closes the window as the app quits, without asking: a merge reports whether what it shows
  /// is saved, as closing it does, and a comparison reports that it was cancelled, so that Git
  /// compares no further files.
  public func closeAsTheAppQuits() {
    if saving == nil {
      cancel()
    } else {
      close()
    }
  }

  /// Whether the result of a merge, or a file of a comparison, has changes that are not saved,
  /// which closing asks about.
  public var hasUnsavedChanges: Bool {
    isResultEdited || hasChangedFiles
  }

  /// Closes the window and reports that the session was cancelled: Git leaves a merge unresolved
  /// and compares no further files.
  public func cancel() {
    finish(.cancelled)
    close()
  }

  /// Reports that the session ended with `outcome`, unless it was reported already.
  func finish(_ outcome: SessionOutcome) {
    guard !hasFinished else { return }
    hasFinished = true
    onFinish?(outcome)
  }
}

extension SessionWindowController: NSUserInterfaceValidations {
  /// Whether the command of `item` can have an effect now.
  ///
  /// A menu item of a comparison mode, Synchronize Scrolling and a source toggle show a
  /// checkmark while they are in effect; a command that switches something on and off takes the
  /// name that says what it does now, such as Show Base while the base is hidden.
  public func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
    if let menuItem = item as? NSMenuItem, let choice = ResultFormatChoice(item: menuItem) {
      return validate(choice, item: menuItem)
    }
    if let menuItem = item as? NSMenuItem, let choice = SyntaxChoice(item: menuItem) {
      return validate(choice, item: menuItem)
    }
    guard let command = SessionCommand(action: item.action) else { return false }
    if let menuItem = item as? NSMenuItem {
      if let mode = command.comparisonMode {
        menuItem.state = mode == comparisonOptions.mode ? .on : .off
      } else if let arrangement = command.lineArrangement {
        menuItem.state = arrangement == presentation.lineArrangement ? .on : .off
      } else if [
        .toggleScrollSynchronization, .toggleSyntaxHighlighting, .toggleLineWrapping,
        .toggleIdenticalFiles,
      ].contains(command) {
        // The window's own state, also while the command can have no effect, as Synchronize
        // Scrolling in a single column, which the panes side by side keep for their return.
        menuItem.state = isSwitchedOn(command) ? .on : .off
      }
      if command == .toggleIgnoreRules {
        // The window's own state, as with every checked item, also while the command can have
        // no effect; a merge never uses the rules.
        menuItem.state =
          usesIgnoreRules && presentation.changes.session.kind == .diff ? .on : .off
        menuItem.toolTip = ignoreRulesHelp
      }
      if let alternateTitle = command.alternateTitle {
        menuItem.title = isSwitchedOn(command) ? alternateTitle : command.title
      }
      if let role = command.toggledRole {
        menuItem.state = isSourceOn(role) ? .on : .off
      }
      if command.chosenRoles != nil {
        menuItem.state = command == currentChoice ? .on : .off
      }
    }
    return canPerform(command)
  }

  /// Whether what `command` switches is on: the base hidden, the result maximized, the
  /// invisible characters shown, the footer hidden.
  func isSwitchedOn(_ command: SessionCommand) -> Bool {
    switch command {
    case .toggleFooter: !settings.showsFooter
    case .toggleBase: !layout.showsBase
    case .toggleResultMaximized: layout.maximizesResult
    case .toggleInvisibles: presentation.allPanes.contains(where: \.showsInvisibles)
    case .toggleIgnoredChanges: presentation.showsIgnoredChanges
    case .toggleScrollSynchronization: presentation.scrollSync.isEnabled
    case .toggleSyntaxHighlighting: highlightsSyntax
    case .toggleLineWrapping: presentation.wrapsLines
    case .toggleIdenticalFiles: collectionNavigator?.filter.showsIdenticalFiles ?? false
    default: false
    }
  }

  /// Whether `command` can have an effect now; while the window cannot show the lines of its
  /// files, or makes ready the comparison that undo or redo brings back, only skipping the
  /// remaining files, the commands of the list, and in a window of several files the patch of
  /// all of them and saving the changes of the others can.
  func canPerform(_ command: SessionCommand) -> Bool {
    let takesCommandsOfTheLines =
      if case .ready = phase { comparisonSwitcher.bringingBack == nil } else { false }
    if !takesCommandsOfTheLines,
      ![
        .skipRemainingFiles, .toggleFooter, .nextFile, .previousFile, .filterFiles,
        .toggleIdenticalFiles, .copyPatch, .exportPatch, .save, .saveAndClose,
      ].contains(command)
    {
      return false
    }
    if binaryMerge != nil {
      return command == .leaveUnresolved || command == .toggleFooter
    }
    return switch command.requirement {
    case .jumpTarget(let jump):
      presentation.navigation.target(of: jump) != nil
    case .moveEnd:
      presentation.otherEndOfMove != nil
    case .anotherPane:
      focusablePanes.count > 1
    case .anotherFile(let forward):
      collectionNavigator?.neighborIndex(forward: forward) != nil
    case .comparedFolders:
      collection?.folders != nil
    case .fileList:
      collectionLayout?.hasList == true
    case .search(let action):
      presentation.search.validate(action)
    case .replacing:
      presentation.search.showsReplaceField && presentation.search.hasFoundMatches
    case .noComparisonUnderWay:
      !comparisonSwitcher.isComparing
    case .ignoreRules:
      presentation.changes.session.kind == .diff && hasEffectiveIgnoreRule
        && !comparisonSwitcher.isComparing
    case .basePane:
      presentation.changes.hasBase && !layout.maximizesResult
    case .panesSideBySide:
      presentation.lineArrangement != .singleColumn
    case .singleColumn:
      presentation.canShowSingleColumn
    case .collapsedRows:
      presentation.canShowAllRows
    case .ignoredChanges:
      presentation.hasPlacesOfIgnoredChanges
    case .collapsibleRows:
      presentation.canCollapseUnchangedRows(caretLine: caretLineInTextMode)
    case .largerFontSize:
      fontSize < Self.fontSizes[Self.fontSizes.count - 1]
    case .smallerFontSize:
      fontSize > Self.fontSizes[0]
    case .otherFontSize:
      fontSize != settings.fontSize
    case .fileOnDisk:
      editableFileURL != nil
    case .blockText:
      !blockText(at: CopiedPlace(pane: focusedPane, block: presentation.currentBlock)).isEmpty
    case .patch:
      hasPatch
    case .resultPane:
      layout.resultPane != nil
    case .swappableSides:
      presentation.arrangement.canSwapSides
    case .remainingFiles:
      collection == nil && context.difftool?.hasFilesAfterThisOne ?? false
    case .choice(let roles):
      decisionPlan(choosing: roles).map { !$0.isEmpty } ?? false
    case .toggle(let role):
      decisionPlan(toggling: role).map { !$0.isEmpty } ?? false
    case .currentResultBlock:
      currentResultBlock != nil && layout.resultPane?.isShown == true
    case .resettableBlock:
      currentResultBlock.map { presentation.result?.document.canReset($0) ?? false } ?? false
    case .resettableConflicts:
      presentation.result?.document.canResetConflicts ?? false
    case .resettableBlocks:
      presentation.result?.document.canResetAll ?? false
    case .openConflicts:
      (presentation.result?.document.openConflictCount ?? 0) > 0
    case .result:
      saving != nil && !comparisonSwitcher.isComparing && !isAskingToClose
    case .changes:
      (saving != nil || hasChangedFiles) && !comparisonSwitcher.isComparing && !isAskingToClose
        && !diskWatch.isReloading
    case .waitingCaller:
      saving != nil && context.waitingCaller != nil && !isAskingToClose
    case .ownFiles:
      context.waitingCaller == nil && context.difftool == nil && !comparisonSwitcher.isComparing
    case .copy(let direction, let allChanges):
      canCopy(direction, allChanges: allChanges)
    case .nothing:
      true
    }
  }
}

extension SessionWindowController: SessionPresentationDelegate {
  func presentationDidChangeCurrentBlock(_ presentation: SessionPresentation) {
    stateDidChange()
  }

  func presentationDidChangeResult(_ presentation: SessionPresentation) {
    stateDidChange()
  }

  func presentation(
    _ presentation: SessionPresentation, didMoveInsertionPointTo selection: NSRange
  ) {
    resultUndo.endTypingRun(unlessContinuedAt: selection)
    updateFooter()
  }

  func presentationDidChangeCollapsedRows(_ presentation: SessionPresentation) {
    updateFooter()
  }

  func presentationDidTakeOverUnannouncedChange(_ presentation: SessionPresentation) {
    resultUndo.endTypingRun()
    sessionUndoManager.removeAllActions()
  }

  func presentation(
    _ presentation: SessionPresentation, didType step: UndoStep, at range: Range<Int>, caret: Int
  ) {
    resultUndo.recordTyping(step, at: range, caret: caret)
  }

  func presentationWillReplaceMatches(_ presentation: SessionPresentation) {
    resultUndo.beginReplacement()
  }

  func presentation(
    _ presentation: SessionPresentation, didReplaceAllMatches replacesAll: Bool
  ) {
    resultUndo.endReplacement(named: PaneSearch.undoActionName(replacingAll: replacesAll))
  }

  func presentation(
    _ presentation: SessionPresentation, didAskToSwitchToggle toggle: Int, ofBlock block: Int
  ) {
    guard let result = presentation.result else { return }
    let changedBlock = presentation.changes.blocks[block]
    let toggles = result.document.toggles(in: changedBlock)
    guard toggles.indices.contains(toggle), let role = toggles[toggle].roles.first else { return }
    presentation.setCurrentBlock(block)
    perform(.toggle(role))
  }

  func presentation(_ presentation: SessionPresentation, didAskToResetBlock block: Int) {
    presentation.setCurrentBlock(block)
    perform(.resetChange)
  }

  func presentation(
    _ presentation: SessionPresentation, menuFor hit: PaneHit, in pane: PaneView
  ) -> NSMenu {
    contextMenu(for: hit, in: pane)
  }
}

extension SessionWindowController: SessionLayoutDelegate {
  func layout(_ layout: SessionSplitViewController, menuForHeaderOf role: Role?) -> NSMenu? {
    headerMenu(for: role)
  }
}
