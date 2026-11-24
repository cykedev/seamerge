import AppKit
import MergeModel
import PaneKit
import SyntaxKit
import os

/// Shows a session in the panes of a window: what each pane shows, the marks of the overview
/// bars, the collapsed runs of unchanged rows, the current block, and the coupling that keeps the
/// panes at the same place while one of them scrolls; in a merge also the result and the signs of
/// its decision column.
///
/// The panes side by side share one row grid while they line up their lines; otherwise each
/// shows the lines of its file, and the seams between them connect their changes. The result of
/// a merge has rows of its own, which its scroll map relates to the grid. A comparison can show
/// both files in a single column instead, whose rows relate to the grid through the lines they
/// show.
@MainActor
final class SessionPresentation {
  /// The changed blocks, as every pane numbers them.
  private(set) var changes: SessionChanges

  /// Which input each pane shows, and whether a result stands below them.
  private(set) var arrangement: PaneArrangement

  /// The result of a merge as it stands, or `nil` for a comparison.
  private(set) var result: ResultState?

  /// The session, with the result of a merge as it stands.
  ///
  /// It is made anew on each access, which copies the session; code that reads it repeatedly
  /// takes it into a constant first, and code that only needs the result reads ``result``.
  var shown: ShownSession {
    result.map(ShownSession.merge) ?? .comparison(changes.session)
  }

  /// The index of the current block among the changed blocks, or `nil` if there is none.
  ///
  /// Every pane tints the current block more strongly and the overview bars point at it.
  private(set) var currentBlock: Int?

  /// While no block is current after a copy, the index of the first block after the place
  /// where the copied block was, from which the jumps go on; `nil` otherwise.
  private(set) var blockAfterPlace: Int?

  /// The bar beside the panes side by side, which is their scroller.
  let sourcesOverviewBar = OverviewBar()

  /// The bar beside the result, which is its scroller, if there is a result.
  let resultOverviewBar: OverviewBar?

  /// The decision column beside the result, if there is a result.
  let decisionColumn: DecisionColumnView?

  /// The bar beside the single column, which is its scroller, if the window can show one.
  let columnOverviewBar: OverviewBar?

  /// The layout of the single column while it shows, or `nil` while the panes side by side do.
  var columnLayout: SingleColumnLayout?

  /// The changed runs of the single column while it shows, which its pane does not retain.
  var columnHighlights: BlockHighlights?

  /// The tokens of the single column while it shows, which its pane does not retain.
  var columnSyntax: ColumnSyntaxTokens?

  /// The coupling of the panes, which keeps them at the same place while one of them scrolls.
  let scrollSync = ScrollSync()

  /// The search over the panes, whose find bar the window shows below them.
  let search: PaneSearch

  /// The alignment of the inputs, which keeps their rows level while long lines wrap.
  let rowAlignment = RowAlignment()

  /// Whether the panes side by side line up their lines on the grid, with filler rows where a
  /// side has fewer lines, or else show the lines of their files as they are, connected by bands
  /// in the seams between them.
  private(set) var alignsLines: Bool

  /// The lines of the inputs without filler rows and how they end, worked out when a pane first
  /// needs them.
  var lines: InputLines

  /// The lines that differ in a way that the comparison mode ignores, once the panes side by
  /// side show the session.
  private(set) var ignoredDifferences: IgnoredDifferences? {
    didSet { hasIgnoredChangePlaces = nil }
  }

  /// Whether a pane side by side has a place where its lines differ in a way that the comparison
  /// mode ignores, once asked; lines that differ only in their line endings have none.
  private var hasIgnoredChangePlaces: Bool?

  /// Whether the panes side by side have a place where their lines differ in a way that the
  /// comparison mode ignores, which Show Ignored Changes would highlight.
  var hasPlacesOfIgnoredChanges: Bool {
    if let hasIgnoredChangePlaces { return hasIgnoredChangePlaces }
    guard let ignoredDifferences else { return false }
    let hasPlaces = PreparedSession.hasPlaces(
      of: ignoredDifferences, in: layout.sourcePanes.map(\.role), of: changes.session)
    hasIgnoredChangePlaces = hasPlaces
    return hasPlaces
  }

  /// Whether the panes above the result highlight the places where their lines differ in a way
  /// that the comparison mode ignores.
  var showsIgnoredChanges = false {
    didSet {
      guard showsIgnoredChanges != oldValue else { return }
      scrollSync.withoutFollowing(showSourceContents)
      showColumn()
    }
  }

  /// Whether the panes wrap long lines at their width.
  var wrapsLines = false {
    didSet {
      for pane in allPanes {
        pane.wrapsLines = wrapsLines
      }
    }
  }

  /// Learns when the current block changes and supplies the context menus of the panes; the
  /// presentation does not retain it.
  weak var delegate: (any SessionPresentationDelegate)?

  /// Tells VoiceOver what changed; by default an announcement of the window of the panes.
  lazy var announce: (String) -> Void = { [weak self] text in
    guard let window = self?.layout.view.window else { return }
    NSAccessibility.post(
      element: window, notification: .announcementRequested,
      userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
  }

  /// The accessibility settings, of which the presentation reads whether movement is reduced
  /// and whether the toggles take the keyboard focus.
  var displayOptions: DisplayOptions {
    didSet { decisionColumn?.navigatesWithKeyboard = displayOptions.navigatesWithKeyboard }
  }

  /// The rotors of VoiceOver through the conflicts and the changes, which every pane offers.
  private var blockRotors: BlockRotors?

  /// The observer of the selection of the result, which makes the block of the insertion point
  /// current.
  private var selectionObserver: (any NSObjectProtocol)?

  /// Whether the result is to be shown anew once a change of its text that nobody announced is
  /// over.
  private var showsResultAnewSoon = false

  /// Whether a command is changing the text of the result, during which the insertion point
  /// moves with the text rather than by the user.
  var isCarryingOut = false

  /// Whether the result can be edited, by typing or by replacing matches of the search; it
  /// cannot while the window makes ready a comparison that undo or redo brings back, and the
  /// result pane then reads as text that cannot be changed.
  var acceptsEdits = true {
    didSet { layout.resultPane?.editingDelegate = acceptsEdits ? self : nil }
  }

  /// The edit of the result that the result pane has asked about and is about to report as
  /// carried out, with the plan that the document made for it.
  var pendingTyping: (plan: EditPlan, edits: [PaneEdit])?

  /// The panes of the window and their headers.
  let layout: SessionSplitViewController

  /// The headers of the inputs, whose names the panes, the toggles and the previews use.
  private(set) var headers: [Role: SideHeader]

  /// The runs of unchanged rows, which ones are collapsed and which the user expanded.
  var collapsed: CollapsedRows {
    didSet {
      if collapsed.runs != oldValue.runs || collapsed.expandedRuns != oldValue.expandedRuns {
        delegate?.presentationDidChangeCollapsedRows(self)
      }
    }
  }
  private var highlights: [BlockHighlights] = []

  /// The tokens of the files, by which the panes color their code.
  let syntax: SessionSyntax

  /// Shows `session` in the panes of `layout`, arranged as `arrangement` says: a merge as
  /// loaded, every conflict open and every other change taken as the merge takes it, with the
  /// first open conflict current, or the first change if no conflict is open.
  ///
  /// - Parameters:
  ///   - headers: The headers of the inputs, whose names the panes take for VoiceOver.
  ///   - resultHeader: The header of the result, if there is one.
  ///   - language: The language the code is colored as, or `nil` if it is not colored.
  ///   - alignsLines: Whether the panes side by side line up their lines on the grid, or connect
  ///     their changes with bands.
  ///   - search: The search over the panes, which the presentation gives the rows to go through.
  init(
    session: Session, arrangement: PaneArrangement, layout: SessionSplitViewController,
    headers: [Role: SideHeader], resultHeader: ResultHeader?, displayOptions: DisplayOptions,
    language: LanguageDescription?, alignsLines: Bool, search: PaneSearch
  ) {
    let result = ShownSession(loading: session, removalNotes: Self.removalNotes(headers: headers))
      .result
    self.arrangement = arrangement
    self.layout = layout
    self.headers = headers
    self.displayOptions = displayOptions
    self.alignsLines = alignsLines
    self.search = search
    self.result = result
    changes = SessionChanges(session: session, origin: arrangement.origin)
    collapsed = CollapsedRows(session: session, document: result?.document)
    lines = InputLines(session: session)
    resultOverviewBar = layout.resultPane.map { _ in OverviewBar() }
    columnOverviewBar = layout.columnPane.map { _ in OverviewBar() }
    decisionColumn = layout.resultPane.map { _ in DecisionColumnView() }
    syntax = SessionSyntax(language: language)

    nameSourcePanes()
    layout.resultPane?.setAccessibilityLabel(resultHeader?.spokenName)
    let theme = displayOptions.theme
    for bar in overviewBars {
      bar.theme = theme
      bar.delegate = self
    }
    layout.sourcePanes.last?.pane.overviewBar = sourcesOverviewBar
    layout.resultPane?.overviewBar = resultOverviewBar
    layout.columnPane?.overviewBar = columnOverviewBar
    decisionColumn?.theme = theme
    decisionColumn?.navigatesWithKeyboard = displayOptions.navigatesWithKeyboard
    decisionColumn?.delegate = self
    layout.resultPane?.decisionColumn = decisionColumn
    for pane in allPanes {
      pane.delegate = self
    }
    // The single column couples with nothing.
    for pane in allPanes where pane !== layout.columnPane {
      scrollSync.add(pane)
    }
    if alignsLines {
      for (_, pane) in layout.sourcePanes {
        rowAlignment.add(pane)
      }
    } else {
      layout.showsSeams = true
    }
    connectPanes()
    search.delegate = self
    search.replaceablePane = layout.resultPane
    syntax.onLexed = { [weak self] in self?.showSyntax() }
    showSession()
    let blockRotors = BlockRotors(presentation: self)
    self.blockRotors = blockRotors
    for pane in allPanes {
      pane.documentView.setAccessibilityCustomRotors(blockRotors.rotors)
    }
    if let resultPane = layout.resultPane {
      resultPane.editingDelegate = self
      selectionObserver = NotificationCenter.default.addObserver(
        forName: NSTextView.didChangeSelectionNotification, object: resultPane.documentView,
        queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.followInsertionPoint() }
      }
    }
    setCurrentBlock(navigation.firstOpenConflict ?? navigation.firstChange)
  }

  isolated deinit {
    if let selectionObserver {
      NotificationCenter.default.removeObserver(selectionObserver)
    }
  }

  /// Makes the block in which the insertion point of the result stands current, while the result
  /// has the focus.
  ///
  /// A block command then acts where the user types. Outside every changed block, the current
  /// block stays.
  func followInsertionPoint() {
    guard !isCarryingOut, pendingTyping == nil else { return }
    updateResultExpandedRuns()
    guard let resultPane = layout.resultPane, let result,
      resultPane.documentView.window?.firstResponder === resultPane.documentView
    else { return }
    delegate?.presentation(self, didMoveInsertionPointTo: resultPane.documentView.selectedRange())
    let caret = resultPane.documentView.selectedRange().location
    guard caret <= result.resultText.paneLength else { return }
    let row = result.row(ofPaneOffset: caret)
    guard let block = resultPane.content.blocks.firstIndex(where: { $0.rows.contains(row) }) else {
      return
    }
    setCurrentBlock(block)
  }

  /// The line that the preview of a conflict shows in place of the lines of a side that removed
  /// them, with the side's name.
  private static func removalNotes(headers: [Role: SideHeader]) -> [Role: String] {
    var notes: [Role: String] = [:]
    for role in [Role.a, .b] {
      guard let name = headers[role]?.distinctName else { continue }
      notes[role] = String(
        localized: "\(name) removed these lines", bundle: .module,
        comment: "Preview of a conflict in place of the lines a side removed, such as main.")
    }
    return notes
  }

  /// Draws the overview bars and the decision column with `theme`.
  func apply(_ theme: Theme) {
    for bar in overviewBars {
      bar.theme = theme
    }
    decisionColumn?.theme = theme
  }

  /// The overview bars: beside the panes side by side, beside the result and beside the single
  /// column, as far as the window has them.
  private var overviewBars: [OverviewBar] {
    [sourcesOverviewBar] + [resultOverviewBar, columnOverviewBar].compactMap(\.self)
  }

  /// Every pane: the inputs from left to right, then the single column and the result, as far as
  /// the window has them, whether they are in view or not.
  var allPanes: [PaneView] {
    layout.sourcePanes.map(\.pane) + [layout.columnPane, layout.resultPane].compactMap(\.self)
  }

  /// Where the current block lies among the changed blocks, and where the others lie.
  var navigation: BlockNavigation {
    BlockNavigation(
      isOpenConflict: changes.blocks.map { result?.document.segment(for: $0).state == .open },
      current: currentBlock, blockAfterPlace: blockAfterPlace)
  }

  /// The block at the other end of the move that the current block is an end of, if it is one.
  var otherEndOfMove: Int? {
    currentBlock.flatMap { changes.otherEndOfMove(fromBlock: $0) }
  }

  /// Makes `block` the current block in every pane and both overview bars.
  func setCurrentBlock(_ block: Int?) {
    blockAfterPlace = nil
    guard block != currentBlock else { return }
    currentBlock = block
    for pane in allPanes {
      pane.currentBlock = block
    }
    for bar in overviewBars {
      bar.currentBlock = block
    }
    delegate?.presentationDidChangeCurrentBlock(self)
  }

  /// Shows `headers` above the panes of the inputs, as the files of a session shown anew have
  /// them.
  func show(_ headers: [Role: SideHeader]) {
    guard headers != self.headers else { return }
    self.headers = headers
    layout.show(arrangement.sourceRoles.compactMap { headers[$0] })
    nameSourcePanes()
  }

  /// Gives each pane side by side the name of the input it shows, for VoiceOver.
  private func nameSourcePanes() {
    for (role, pane) in layout.sourcePanes {
      pane.setAccessibilityLabel(headers[role]?.spokenName)
    }
  }

  /// How the panes show the session now, which decides what each of them shows.
  var setup: PaneSetup {
    PaneSetup(
      arrangement: arrangement, alignsLines: alignsLines, baseIsShown: layout.showsBase,
      showsIgnoredChanges: showsIgnoredChanges,
      columnFirstSide: columnLayout != nil ? arrangement.leadingRole : nil,
      seams: layout.seams.compactMap { seam in
        guard let left = seam.leftPane.flatMap(role(of:)),
          let right = seam.rightPane.flatMap(role(of:))
        else { return nil }
        return PaneSetup.Seam(left: left, right: right)
      },
      // Only the decision column of a merge names the inputs; the panes of a comparison are the
      // same whatever its files are called, also while a window shows the names of files it
      // waits for.
      headers: arrangement.showsResult ? headers : [:],
      tabWidth: layout.sourcePanes.first?.pane.theme.tabWidth ?? Theme().tabWidth)
  }

  /// Shows the session in every pane anew, with the runs collapsed now: the contents, the
  /// collapsed runs, the marks of the overview bars and, in a merge, the signs of the decision
  /// column.
  private func showSession() {
    show(PreparedSession(shown, setup: setup, lines: lines, collapsed: collapsed))
  }

  /// Puts `prepared` in place in every pane: the session and the result it was made for, the
  /// collapsed runs, the marks of the overview bars and, in a merge, the signs of the decision
  /// column.
  ///
  /// - Precondition: `prepared` was made for the setup of the panes now.
  private func show(_ prepared: PreparedSession) {
    precondition(prepared.setup == setup, "Contents made for another setup of the panes")
    result = prepared.shown.result
    changes = prepared.changes
    collapsed = prepared.collapsed
    ignoredDifferences = prepared.ignoredDifferences
    hasIgnoredChangePlaces = prepared.hasPlacesOfIgnoredChanges
    lines = prepared.lines
    connectPanes()
    defer { updateSearchSections() }
    scrollSync.withoutFollowing {
      highlights = []
      for (source, (_, pane)) in zip(prepared.sources, layout.sourcePanes) {
        show(
          source.content, prepared: source.prepared, collapsedRuns: source.collapsedRuns,
          of: source.role, in: pane)
      }
    }
    showSeamBands(prepared.blocksWithoutBand)
    showOverviewGrid()
    alignSourcesToB()
    sourcesOverviewBar.marks = prepared.sourceMarks
    if let column = prepared.column {
      showColumn(column)
    }
    syntax.lexInputs(of: changes.session)
    showSyntax()
    guard let result, let resultPane = layout.resultPane, let resultContent = prepared.resultPane
    else { return }
    syntax.lexResult(result.rows)
    showSyntax()
    if let prepared = resultContent.prepared {
      resultPane.setContent(prepared, collapsedRuns: resultContent.collapsedRuns)
    } else {
      resultPane.setContent(
        resultContent.content.content, collapsedRuns: resultContent.collapsedRuns)
    }
    resultPane.expandedRuns = resultExpandedRuns
    resultOverviewBar?.marks = resultContent.marks
    decisionColumn?.decisions = resultContent.content.decisions
  }

  /// Shows the inputs in the panes side by side, on the grid or with the lines of their files as
  /// they are, with their collapsed runs.
  ///
  /// The panes get their contents one after the other without following each other, since
  /// until all of them have theirs, they show different blocks; they stand together again
  /// afterwards.
  func showSources() {
    scrollSync.withoutFollowing(showSourceContents)
    showSeamBands()
    showOverviewGrid()
    alignSourcesToB()
    updateSearchSections()
  }

  /// Gives each pane side by side its content, on the grid or with the lines of its file.
  private func showSourceContents() {
    let ignoredDifferences = IgnoredDifferences(in: changes.session)
    self.ignoredDifferences = ignoredDifferences
    let setup = setup
    highlights = []
    for (role, pane) in layout.sourcePanes {
      let content = PreparedSession.sourceContent(
        of: role, setup: setup, changes: changes, document: result?.document,
        ignoredDifferences: ignoredDifferences, lines: &lines)
      show(content, collapsedRuns: sourceRuns(in: role), of: role, in: pane)
    }
  }

  /// Gives `pane`, the pane side by side of `role`, `content` with `collapsedRuns`, the runs
  /// the user expanded, and the changed runs within the lines of its blocks; `prepared` is the
  /// content prepared for it away from the main actor, if it was.
  private func show(
    _ content: PaneContent, prepared: PreparedPaneContent? = nil, collapsedRuns: [CollapsedRun],
    of role: Role, in pane: PaneView
  ) {
    let provider = BlockHighlights(
      changes: changes, rows: alignsLines ? .grid(role) : .lines(role),
      comparesSides: changes.comparesSides(baseIsShown: layout.showsBase))
    highlights.append(provider)
    pane.highlightProvider = provider
    if let prepared {
      pane.setContent(prepared, collapsedRuns: collapsedRuns)
    } else {
      pane.setContent(content, collapsedRuns: collapsedRuns)
    }
    pane.expandedRuns = sourceExpandedRuns(in: role)
  }

  /// Lines up the lines of the panes side by side on the grid, or shows the lines of their files
  /// as they are and connects their changes with bands: a change of what the window shows, which
  /// the user cannot undo and need not.
  ///
  /// The current block, the insertion point and the selection of each pane, the runs the user
  /// expanded and the block at the reading line stay.
  func setAlignsLines(_ alignsLines: Bool) {
    guard alignsLines != self.alignsLines else { return }
    let place = gridPlaceAtReadingLine
    let selections = layout.sourcePanes.map { role, pane in
      (
        pane: pane, role: role,
        ranges: pane.documentView.selectedRanges.map { textRange($0.rangeValue, in: role) }
      )
    }
    self.alignsLines = alignsLines
    for (_, pane) in layout.sourcePanes {
      if alignsLines {
        rowAlignment.add(pane)
      } else {
        rowAlignment.remove(pane)
      }
    }
    layout.showsSeams = !alignsLines
    connectPanes()
    showSources()
    for (pane, role, ranges) in selections {
      pane.documentView.selectedRanges = ranges.map { NSValue(range: paneRange($0, in: role)) }
    }
    layout.view.layoutSubtreeIfNeeded()
    if let place {
      scroll(toGridPlace: place)
    }
  }

  /// Colors the code of every pane as `language`, or not at all, once its files are lexed anew.
  func colorSyntax(as language: LanguageDescription?) {
    guard language != syntax.language else { return }
    syntax.language = language
    // The panes hold their tokens weakly, so the tokens of the former language are gone
    // already; each pane takes their colors away now.
    for pane in allPanes {
      pane.syntaxProvider = nil
    }
    syntax.lexInputs(of: changes.session)
    if let result {
      syntax.lexResult(result.rows)
    }
    showSyntax()
  }

  /// Gives each pane the tokens of its file or of the result as far as they are known, and takes
  /// away those that are gone.
  private func showSyntax() {
    for (role, pane) in layout.sourcePanes {
      let tokens = syntax.tokens(of: role)
      if pane.syntaxProvider !== tokens {
        pane.syntaxProvider = tokens
      }
    }
    if let resultPane = layout.resultPane, resultPane.syntaxProvider !== syntax.resultTokens {
      resultPane.syntaxProvider = syntax.resultTokens
    }
    showColumnSyntax()
  }

  /// Shows `result`, the result after an edit that the result pane has carried out already, or
  /// after a command whose edits it has carried out, in place of the result shown now.
  ///
  /// The result pane gets the blocks, previews and handwritten rows of the new result, the panes
  /// side by side the tints of decided conflicts, the overview bars their marks and the decision
  /// column its signs. Should the text of the pane have ended its lines otherwise than the
  /// result does, the pane gets the whole content anew.
  ///
  /// With `anew`, the pane gets the whole content of `result`, whatever it shows now.
  ///
  /// The tokens of the result follow `edits`, the edits that led to it, in the offsets of the
  /// pane's text; without them, or with `anew`, the result is lexed anew in the background.
  ///
  /// - Precondition: `resultPane` is the result pane, and it shows the text of `result` unless
  ///   `anew` is set.
  func show(
    _ result: ResultState, in resultPane: PaneView, after edits: [PaneEdit] = [],
    anew: Bool = false
  ) {
    let previousRows = self.result?.rows
    self.result = result
    let content = ResultPaneContent(result: result, changes: changes, headers: headers)
    let keepsLines = !anew && resultPane.content.lineEndings == content.content.lineEndings
    var lexedRows: Range<Int>?
    if keepsLines, let previousRows {
      lexedRows = syntax.resultDidChange(by: edits, from: previousRows, to: result.rows)
    } else {
      syntax.lexResult(result.rows)
    }
    showSyntax()
    if keepsLines {
      resultPane.setBlocks(
        content.content.blocks, previews: content.content.previews,
        rowTints: content.content.rowTints)
      let runs = resultRuns
      if resultPane.collapsedRuns != runs {
        resultPane.collapsedRuns = runs
      }
    } else {
      if !anew {
        Self.logger.error("The result pane ended its lines otherwise than the result")
      }
      resultPane.setContent(content.content, collapsedRuns: resultRuns)
    }
    resultPane.expandedRuns = resultExpandedRuns
    if let lexedRows {
      resultPane.syntaxDidChange(inRows: lexedRows)
    }
    resultOverviewBar?.marks = OverviewMarks.result(
      of: changes, document: result.document, result: content.content)
    decisionColumn?.decisions = content.decisions
    sourcesOverviewBar.marks = OverviewMarks.sources(
      of: changes, document: result.document, arrangement: arrangement,
      baseIsShown: layout.showsBase)
    for (role, pane) in layout.sourcePanes {
      pane.setBlocks(
        PaneContent.blocks(
          source: role, of: changes, document: result.document,
          baseIsShown: layout.showsBase, alignsLines: alignsLines),
        previews: [], rowTints: [:])
    }
    updateSearchSections()
    delegate?.presentationDidChangeResult(self)
  }

  /// Takes `result`, the result after a change of the text of `resultPane` that nobody
  /// announced, without showing it while the pane processes the change, and shows it anew once
  /// the change is over, after any further such changes.
  func takeOverUnannounced(_ result: ResultState, in resultPane: PaneView) {
    self.result = result
    guard !showsResultAnewSoon else { return }
    showsResultAnewSoon = true
    // The pane's content must stay as it is while its text processes the change.
    Task { @MainActor [weak self] in
      guard let self, let result = self.result else { return }
      showsResultAnewSoon = false
      show(result, in: resultPane, anew: true)
      delegate?.presentationDidTakeOverUnannouncedChange(self)
    }
  }

  /// The runs that are collapsed now, in the rows of the pane of `role`: rows of the grid, or
  /// lines of its file.
  private func sourceRuns(in role: Role) -> [CollapsedRun] {
    PreparedSession.sourceRuns(
      of: collapsed.runs, in: role, collapsed: collapsed, alignsLines: alignsLines)
  }

  /// The rows of `run` in the pane of `role`: rows of the grid, or lines of its file.
  private func rows(of run: CollapsedRows.Run, in role: Role) -> Range<Int> {
    alignsLines ? run.rows : collapsed.lines(of: run, in: role)
  }

  /// The runs that are collapsed now, in lines of the result, if there is one.
  private var resultRuns: [CollapsedRun] {
    resultRuns(of: collapsed.runs)
  }

  /// The runs that the user expanded and that may collapse again, in the rows of the pane of
  /// `role`.
  private func sourceExpandedRuns(in role: Role) -> [CollapsedRun] {
    collapsed.expandedRuns.map { CollapsedRun(rows: rows(of: $0, in: role)) }
  }

  /// The runs that the user expanded and that may collapse again, in lines of the result, if
  /// there is one; not the one of the insertion point while the result has the focus, which
  /// collapsing would hide, as Collapse Unchanged Lines leaves it out too.
  private var resultExpandedRuns: [CollapsedRun] {
    let runs = resultRuns(of: collapsed.expandedRuns)
    guard let resultPane = layout.resultPane, let result,
      resultPane.documentView.window?.firstResponder === resultPane.documentView
    else { return runs }
    let caret = resultPane.documentView.selectedRange().location
    guard caret <= result.resultText.paneLength else { return runs }
    let row = result.row(ofPaneOffset: caret)
    return runs.filter { !$0.rows.contains(row) }
  }

  /// Gives the result the runs that may collapse again, after the insertion point or the focus
  /// moved.
  func updateResultExpandedRuns() {
    layout.resultPane?.expandedRuns = resultExpandedRuns
  }

  /// `runs` in lines of the result, if there is one, without those that hide no line there.
  private func resultRuns(of runs: [CollapsedRows.Run]) -> [CollapsedRun] {
    guard let result else { return [] }
    return PreparedSession.resultRuns(of: runs, collapsed: collapsed, result: result)
  }

  /// Gives every pane the runs that are collapsed now.
  func showCollapsedRuns() {
    for (role, pane) in layout.sourcePanes {
      pane.collapsedRuns = sourceRuns(in: role)
      pane.expandedRuns = sourceExpandedRuns(in: role)
    }
    showOverviewGrid()
    alignSourcesToB()
    showColumnRuns()
    layout.resultPane?.collapsedRuns = resultRuns
    layout.resultPane?.expandedRuns = resultExpandedRuns
  }

  /// Shows `shown`, the same files compared anew, and keeps the line of B at the reading line
  /// where it is.
  func show(_ shown: ShownSession) {
    showComparedAnew(PreparedSession(shown, setup: setup, lines: lines))
  }

  /// What the panes show for `shown`, the same files compared anew, made away from the main
  /// actor for the setup of the panes now; `nil` if the setup changed meanwhile, for which the
  /// contents are to be made anew.
  ///
  /// With `collapsed`, the panes collapse its runs, else every run that collapses in a new
  /// window.
  ///
  /// - Precondition: `collapsed` holds the runs of the session of `shown`.
  func prepare(
    _ shown: ShownSession, collapsed: CollapsedRows? = nil
  ) async -> PreparedSession? {
    let setup = setup
    let prepared = await PreparedSession.concurrently(
      shown, setup: setup, lines: lines, collapsed: collapsed)
    return prepared.setup == self.setup ? prepared : nil
  }

  /// What the panes show for `session`, the comparison that a window without lines waited for or
  /// another file of a window that compares several, as loaded, made away from the main actor
  /// for the setup of the panes once it is ready: a merge with every conflict open and every
  /// other change taken as the merge takes it.
  func prepareLoaded(_ session: Session) async -> PreparedSession {
    while true {
      let setup = setup
      let prepared = await Self.prepareLoaded(
        session, setup: setup, removalNotes: Self.removalNotes(headers: headers))
      if prepared.setup == self.setup {
        return prepared
      }
    }
  }

  @concurrent
  private static func prepareLoaded(
    _ session: Session, setup: PaneSetup, removalNotes: [Role: String]
  ) async -> PreparedSession {
    await PreparedSession.concurrently(
      ShownSession(loading: session, removalNotes: removalNotes), setup: setup,
      lines: InputLines(session: session))
  }

  /// Shows `prepared`, the comparison that a window without lines waited for, as a new window
  /// shows it: with the first open conflict current, or the first change if no conflict is
  /// open, in view.
  ///
  /// - Precondition: `prepared` was made for the setup of the panes now.
  func showLoaded(_ prepared: PreparedSession) {
    show(prepared)
    currentBlock = nil
    setCurrentBlock(navigation.firstOpenConflict ?? navigation.firstChange)
    showCurrentBlock()
  }

  /// Shows `prepared`, made for the same files compared anew, and keeps the line of B at the
  /// reading line where it is.
  ///
  /// The block that holds the first line of the current block in B stays current, or the next
  /// changed block after it; the runs that the user expanded collapse again.
  ///
  /// - Precondition: `prepared` was made for the setup of the panes now.
  func showComparedAnew(_ prepared: PreparedSession) {
    let currentLineOfB = currentBlock.map { changes.blocks[$0].lines(in: .b).lowerBound }
    keepingTheLineOfBInPlace {
      show(prepared)
    }
    let rowLayout = changes.session.rowLayout
    currentBlock = nil
    setCurrentBlock(
      currentLineOfB.flatMap { line in
        // B may have become shorter than the line, or empty, which leaves its place at the top.
        let lineCount = rowLayout.lineCount(in: .b)
        let row = lineCount > 0 ? rowLayout.row(ofLine: min(line, lineCount - 1), in: .b) : 0
        return changes.blocks.firstIndex { rowLayout.rows(of: $0).upperBound > row }
      })
  }

  /// Shows `prepared`, the comparison after a copy of a change or after its undo or redo, with
  /// the line of the input of `role` that was at the reading line where it was, and `block` as
  /// the current block; with none, the jumps go on from before `nextBlock`.
  ///
  /// The input that the text was copied from keeps its lines, so its line keeps the place of
  /// the text the user looked at.
  ///
  /// - Precondition: `prepared` was made for the setup of the panes now.
  func showCopied(
    _ prepared: PreparedSession, keepingTheLineOf role: Role, current block: Int?,
    before nextBlock: Int?
  ) {
    keepingTheLine(of: role) {
      show(prepared)
    }
    currentBlock = nil
    setCurrentBlock(block)
    blockAfterPlace = block == nil ? nextBlock : nil
  }

  /// Shows `prepared`, the comparison of other files, from its top with no current block, as a
  /// window that compares several files does when the user goes to another file.
  ///
  /// - Precondition: The window shows a comparison, which has no result, and `prepared` was made
  ///   for the setup of the panes now, as ``prepareLoaded(_:)`` makes it.
  func showOtherFiles(_ prepared: PreparedSession) {
    precondition(!arrangement.showsResult, "Only a comparison shows other files in its panes")
    // The panes show the blocks of the old files until each has the new ones.
    scrollSync.withoutFollowing { show(prepared) }
    currentBlock = nil
    setCurrentBlock(nil)
    leadingPane?.scroll(toPlaceRowAtReadingLine: 0, motion: .cut)
  }

  /// Puts the two sides of a comparison the other way round: each pane shows the other side,
  /// with its header, color and markers, so that an insertion reads as a removal; the current
  /// block, the expanded runs and the place at the reading line stay.
  ///
  /// - Precondition: The sides can change places.
  func swapSides() {
    arrangement.swapSides()
    keepingTheLineOfBInPlace {
      layout.show(arrangement.sourceRoles.compactMap { headers[$0] })
      changes = SessionChanges(session: changes.session, origin: arrangement.origin)
      nameSourcePanes()
      connectPanes()
      showSession()
    }
    for pane in allPanes {
      pane.currentBlock = currentBlock
    }
  }

  /// Shows the panes side by side again, after the base came into view or went out of it,
  /// which decides the pane that carries the marks of conflicts, the panes on the track and the
  /// seams between them.
  func showSourcesAgain() {
    connectPanes()
    showSession()
  }

  /// Puts the panes on the track that are in view now, after the result took the whole window
  /// or gave it back, and brings the panes side by side to where the result stands.
  func resultDidChangeMaximized() {
    connectPanes()
    updateSearchSections()
    guard let resultPane = layout.resultPane, !layout.maximizesResult else { return }
    layout.view.layoutSubtreeIfNeeded()
    scrollSync.align(to: resultPane)
  }

  /// Whether Collapse Unchanged Lines would change what the panes show: all rows show and there
  /// are runs to collapse, or the user expanded runs that would collapse again, leaving out the
  /// one of the line `caretLine` of the result if the insertion point is there.
  func canCollapseUnchangedRows(caretLine: Int?) -> Bool {
    var collapsing = collapsed
    collapsing.collapseUnchangedRows(
      document: result?.document, caretRow: caretRow(ofLine: caretLine))
    return collapsing.runs != collapsed.runs
  }

  /// Whether Show All Lines would change what the panes show: runs are collapsed.
  var canShowAllRows: Bool {
    !collapsed.runs.isEmpty
  }

  /// Shows every row of every pane.
  func showAllRows() {
    collapsed.showAllRows()
    showCollapsedRuns()
  }

  /// Collapses every long run of unchanged rows again, except where the result is worked on and
  /// the run of the line `caretLine` of the result, if the insertion point is there.
  func collapseUnchangedRows(caretLine: Int?) {
    collapsed.collapseUnchangedRows(
      document: result?.document, caretRow: caretRow(ofLine: caretLine))
    showCollapsedRuns()
  }

  /// The row of the grid of line `line` of the result.
  private func caretRow(ofLine line: Int?) -> Int? {
    guard let line, let result else { return nil }
    return result.gridRow(ofLine: line)
  }

  /// The row of the grid at `row` of `pane`: the same row in a pane side by side on the grid,
  /// the row of the line in one without filler rows, the row that a line of the result lies on,
  /// and the row of the line that a row of the single column shows.
  func gridRow(ofRow row: Int, in pane: PaneView) -> Int {
    if pane === layout.resultPane, let result {
      return result.gridRow(ofLine: row)
    }
    if pane === layout.columnPane, let columnLayout {
      return columnLayout.rowCount > 0
        ? gridRow(ofColumnRow: min(max(row, 0), columnLayout.rowCount - 1), in: columnLayout) : 0
    }
    guard !alignsLines, let role = role(of: pane) else { return row }
    let rowLayout = changes.session.rowLayout
    let lineCount = rowLayout.lineCount(in: role)
    guard lineCount > 0 else { return 0 }
    return rowLayout.row(ofLine: min(max(row, 0), lineCount - 1), in: role)
  }

  /// The row of `pane` at `gridRow` of the grid: the same row in a pane side by side on the
  /// grid, the line at the same place of the block in one without filler rows, the line of the
  /// result that lies there, and the row of the single column at the same place of the block.
  func row(ofGridRow gridRow: Int, in pane: PaneView) -> Int {
    if pane === layout.resultPane, let result {
      return result.line(ofGridRow: gridRow)
    }
    if pane === layout.columnPane, let columnLayout {
      return columnRow(ofGridRow: gridRow, in: columnLayout)
    }
    guard !alignsLines, let role = role(of: pane) else { return gridRow }
    let line = Int(gridMap(of: role).targetPosition(at: Double(gridRow)).rounded(.down))
    return min(max(line, 0), max(changes.session.rowLayout.lineCount(in: role) - 1, 0))
  }

  /// The input that `pane`, one of the panes side by side, shows; `nil` for the result.
  func role(of pane: PaneView) -> Role? {
    layout.sourcePanes.first { $0.pane === pane }?.role
  }

  /// Scrolls `pane` so that `line` of its file, counted from 0, lies at the reading line, and
  /// makes its block current if the line belongs to a changed block; a run that hides the line
  /// expands first.
  ///
  /// In a side of a patch, `line` is the number its hunks give the line, and the first line from
  /// there on stands in for one the patch passes over.
  ///
  /// - Returns: The row of the line in `pane`.
  @discardableResult
  func go(toLine line: Int, in pane: PaneView) -> Int {
    let rowLayout = changes.session.rowLayout
    let row: Int
    if pane === layout.resultPane {
      row = min(max(line, 0), pane.content.lineNumbers.count - 1)
    } else if pane === layout.columnPane, let columnLayout {
      // The line counts in the file on the right, the newer one, whose numbers the column shows
      // in its right column.
      let role = PaneContent.otherSide(of: columnLayout.firstSide)
      let lineCount = rowLayout.lineCount(in: role)
      guard lineCount > 0 else { return 0 }
      let line = changes.session.line(numbered: line, in: role)
      row = columnLayout.row(ofLine: min(max(line, 0), lineCount - 1), in: role)
    } else if let role = role(of: pane) {
      let lineCount = rowLayout.lineCount(in: role)
      let line = changes.session.line(numbered: line, in: role)
      let clamped = min(max(line, 0), max(lineCount - 1, 0))
      row = lineCount == 0 || !alignsLines ? clamped : rowLayout.row(ofLine: clamped, in: role)
    } else {
      return 0
    }
    if collapsed.expandToShow(row: gridRow(ofRow: row, in: pane)) {
      showCollapsedRuns()
    }
    if let block = pane.content.blocks.firstIndex(where: { $0.rows.contains(row) }) {
      setCurrentBlock(block)
    }
    pane.scroll(toPlaceRowAtReadingLine: row, motion: motion)
    return row
  }

  /// Runs `body`, which changes how the panes lay out their rows, and scrolls the line of B that
  /// was at the reading line back to it.
  func keepingTheLineOfBInPlace(_ body: () -> Void) {
    keepingTheLine(of: .b, body)
  }

  /// Runs `body`, which changes how the panes lay out their rows, and scrolls the line of the
  /// input of `role` that was at the reading line back to it.
  func keepingTheLine(of role: Role, _ body: () -> Void) {
    let place = place(atReadingLineOf: role)
    body()
    guard let place else { return }
    let rowLayout = changes.session.rowLayout
    if let pane = linesPane(of: role) {
      let line = min(place.line, max(rowLayout.lineCount(in: role) - 1, 0))
      pane.scroll(toPlaceRowAtReadingLine: line, fraction: place.fraction, motion: .cut)
      return
    }
    guard let pane = leadingPane, place.line < rowLayout.lineCount(in: role) else { return }
    let row = rowLayout.row(ofLine: place.line, in: role)
    pane.scroll(
      toPlaceRowAtReadingLine: self.row(ofGridRow: row, in: pane), fraction: place.fraction,
      motion: .cut)
  }

  /// The pane of the input of `role` while it shows the lines of its file without filler rows
  /// and is in view, in which a line of the input is a row of its own.
  private func linesPane(of role: Role) -> PaneView? {
    guard !alignsLines, let pane = layout.sourcePane(role), pane.isShown else { return nil }
    return pane
  }

  /// The line of the input of `role` at the reading line of the panes, or the first line after
  /// it if a filler row is there, with how far down its row the reading line passes; `nil` if
  /// the input has no line from there on.
  private func place(atReadingLineOf role: Role) -> (line: Int, fraction: CGFloat)? {
    if let pane = linesPane(of: role) {
      guard changes.session.rowLayout.lineCount(in: role) > 0 else { return nil }
      let (row, fraction) = pane.rowAtReadingLine
      return (row, fraction)
    }
    guard let pane = leadingPane else { return nil }
    let (hitRow, fraction) = pane.rowAtReadingLine
    let rowLayout = changes.session.rowLayout
    let row = gridRow(ofRow: hitRow, in: pane)
    guard
      let line = (row..<rowLayout.rowCount).lazy.compactMap({ rowLayout.line(atRow: $0, in: role) })
        .first
    else { return nil }
    return (line, rowLayout.line(atRow: row, in: role) == line ? fraction : 0)
  }

  /// Makes `block` current and scrolls it to the reading line of every pane, as far as the text
  /// allows: what every jump of the Go menu does.
  func jump(to block: Int) {
    setCurrentBlock(block)
    let panes =
      scrollSync.isEnabled
      ? [leadingPane(toward: block)].compactMap(\.self) : allPanes.filter(\.isShown)
    for pane in panes {
      pane.scroll(
        toPlaceRowAtReadingLine: pane.content.blocks[block].rows.lowerBound, motion: motion)
    }
  }

  /// Brings the current block into view, at the reading line, unless it is in full view already;
  /// how a window shows its first conflict or change when it opens.
  func showCurrentBlock() {
    guard let currentBlock, let pane = leadingPane(toward: currentBlock),
      !pane.showsWhole(rows: pane.content.blocks[currentBlock].rows)
    else { return }
    pane.scroll(
      toPlaceRowAtReadingLine: pane.content.blocks[currentBlock].rows.lowerBound, motion: .cut)
  }

  /// The pane that the others follow when the window scrolls to a block: the first pane side by
  /// side in view, or the result while those are out of view.
  var leadingPane: PaneView? {
    allPanes.first(where: \.isShown)
  }

  /// The pane that the others follow when the window scrolls to `block`: on the grid and in the
  /// single column the ``leadingPane``; otherwise the pane side by side in view with the most
  /// lines in the block, so that the block comes to the reading line in every pane rather than
  /// the boundary of a pane without its lines, past which the others would follow.
  func leadingPane(toward block: Int) -> PaneView? {
    guard !alignsLines, columnLayout == nil else { return leadingPane }
    return paneWithMostLines(in: changes.blocks[block])?.pane ?? leadingPane
  }

  /// Makes the block of `hit` in `pane` current, if the hit lies in a changed block, and brings
  /// it into view in the other area of a merge, unless it is in full view there already.
  func select(_ hit: PaneHit, in pane: PaneView) {
    guard let block = hit.block else { return }
    setCurrentBlock(block)
    let others =
      pane === layout.resultPane
      ? layout.sourcePanes.map(\.pane) : [layout.resultPane].compactMap(\.self)
    guard let other = others.first(where: \.isShown),
      !other.showsWhole(rows: other.content.blocks[block].rows)
    else { return }
    other.scroll(
      toPlaceRowAtReadingLine: other.content.blocks[block].rows.lowerBound, motion: motion)
  }

  static let logger = Logger(subsystem: "app.eiden.seamerge", category: "SeamergeUI")

  /// How the panes move when they scroll to a block.
  private var motion: PaneView.ScrollMotion {
    displayOptions.reducesMotion ? .cut : .glideWithinAWindowHeight
  }
}
