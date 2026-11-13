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
/// The panes side by side share one row grid. The result of a merge has rows of its own, which
/// its scroll map relates to the grid.
@MainActor
final class SessionPresentation {
  /// The changed blocks, as every pane numbers them.
  private(set) var changes: SessionChanges

  /// Which input each pane shows, and whether a result stands below them.
  private(set) var arrangement: PaneArrangement

  /// The result of a merge as it stands, or `nil` for a comparison.
  private(set) var result: ResultState?

  /// The index of the current block among the changed blocks, or `nil` if there is none.
  ///
  /// Every pane tints the current block more strongly and the overview bars point at it.
  private(set) var currentBlock: Int?

  /// The bar beside the panes side by side, which is their scroller.
  let sourcesOverviewBar = OverviewBar()

  /// The bar beside the result, which is its scroller, if there is a result.
  let resultOverviewBar: OverviewBar?

  /// The decision column beside the result, if there is a result.
  let decisionColumn: DecisionColumnView?

  /// The coupling of the panes, which keeps them at the same place while one of them scrolls.
  let scrollSync = ScrollSync()

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

  /// The observer of the selection of the result, which makes the block of the insertion point
  /// current.
  private var selectionObserver: (any NSObjectProtocol)?

  /// Whether the result is to be shown anew once a change of its text that nobody announced is
  /// over.
  private var showsResultAnewSoon = false

  /// Whether a command is changing the text of the result, during which the insertion point
  /// moves with the text rather than by the user.
  var isCarryingOut = false

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
  init(
    session: Session, arrangement: PaneArrangement, layout: SessionSplitViewController,
    headers: [Role: SideHeader], resultHeader: ResultHeader?, displayOptions: DisplayOptions,
    language: LanguageDescription?
  ) {
    let result =
      arrangement.showsResult
      ? ResultState(session: session, removalNotes: Self.removalNotes(headers: headers)) : nil
    self.arrangement = arrangement
    self.layout = layout
    self.headers = headers
    self.displayOptions = displayOptions
    self.result = result
    changes = SessionChanges(session: session, origin: arrangement.origin)
    collapsed = CollapsedRows(session: session, document: result?.document)
    resultOverviewBar = layout.resultPane.map { _ in OverviewBar() }
    decisionColumn = layout.resultPane.map { _ in DecisionColumnView() }
    syntax = SessionSyntax(language: language)

    nameSourcePanes()
    layout.resultPane?.setAccessibilityLabel(resultHeader?.spokenName)
    let theme = displayOptions.theme
    for bar in [sourcesOverviewBar] + [resultOverviewBar].compactMap(\.self) {
      bar.theme = theme
      bar.delegate = self
    }
    layout.sourcePanes.last?.pane.overviewBar = sourcesOverviewBar
    layout.resultPane?.overviewBar = resultOverviewBar
    decisionColumn?.theme = theme
    decisionColumn?.navigatesWithKeyboard = displayOptions.navigatesWithKeyboard
    decisionColumn?.delegate = self
    layout.resultPane?.decisionColumn = decisionColumn
    for pane in allPanes {
      scrollSync.add(pane)
      pane.delegate = self
    }
    if let resultPane = layout.resultPane {
      for (_, pane) in layout.sourcePanes {
        scrollSync.setRowMapping(
          between: resultPane, and: pane,
          forward: { [weak self] line in self?.result?.scrollMap.row(atResultLine: line) ?? line },
          backward: { [weak self] row in self?.result?.scrollMap.resultLine(atRow: row) ?? row })
      }
    }
    syntax.onLexed = { [weak self] in self?.showSyntax() }
    showSession()
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
    sourcesOverviewBar.theme = theme
    resultOverviewBar?.theme = theme
    decisionColumn?.theme = theme
  }

  /// Every pane: the inputs from left to right, then the result, if there is one.
  var allPanes: [PaneView] {
    layout.sourcePanes.map(\.pane) + [layout.resultPane].compactMap(\.self)
  }

  /// Where the current block lies among the changed blocks, and where the others lie.
  var navigation: BlockNavigation {
    BlockNavigation(
      isOpenConflict: changes.blocks.map { result?.document.segment(for: $0).state == .open },
      current: currentBlock)
  }

  /// Makes `block` the current block in every pane and both overview bars.
  func setCurrentBlock(_ block: Int?) {
    guard block != currentBlock else { return }
    currentBlock = block
    for pane in allPanes {
      pane.currentBlock = block
    }
    sourcesOverviewBar.currentBlock = block
    resultOverviewBar?.currentBlock = block
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

  /// Shows the session in every pane: the contents, the collapsed runs, the marks of the
  /// overview bars and, in a merge, the signs of the decision column.
  private func showSession() {
    let ignoredDifferences = IgnoredDifferences(in: changes.session)
    let sourceRuns = sourceRuns
    highlights = []
    for (role, pane) in layout.sourcePanes {
      let provider = BlockHighlights(changes: changes, role: role)
      highlights.append(provider)
      pane.highlightProvider = provider
      pane.setContent(
        PaneContent(
          source: role, of: changes, document: result?.document,
          ignoredDifferences: ignoredDifferences,
          conflictMarkRole: changes.conflictMarkRole(baseIsShown: layout.showsBase)),
        collapsedRuns: sourceRuns)
      pane.expandedRuns = sourceExpandedRuns
    }
    sourcesOverviewBar.marks = OverviewMarks.sources(
      of: changes, document: result?.document, arrangement: arrangement)
    syntax.lexInputs(of: changes.session)
    showSyntax()
    guard let result, let resultPane = layout.resultPane else { return }
    let content = ResultPaneContent(result: result, changes: changes, headers: headers)
    syntax.lexResult(result.rows)
    showSyntax()
    resultPane.setContent(content.content, collapsedRuns: resultRuns)
    resultPane.expandedRuns = resultExpandedRuns
    resultOverviewBar?.marks = OverviewMarks.result(
      of: changes, document: result.document, result: content.content)
    decisionColumn?.decisions = content.decisions
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
  /// - Precondition: The window shows a merge, and the result pane shows the text of `result`
  ///   unless `anew` is set.
  func show(_ result: ResultState, after edits: [PaneEdit] = [], anew: Bool = false) {
    guard let resultPane = layout.resultPane else {
      preconditionFailure("Only a merge has a result")
    }
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
      of: changes, document: result.document, arrangement: arrangement)
    let conflictMarkRole = changes.conflictMarkRole(baseIsShown: layout.showsBase)
    for (role, pane) in layout.sourcePanes {
      pane.setBlocks(
        PaneContent.blocks(
          source: role, of: changes, document: result.document,
          conflictMarkRole: conflictMarkRole),
        previews: [], rowTints: [:])
    }
    delegate?.presentationDidChangeResult(self)
  }

  /// Takes `result`, the result after a change of the result pane's text that nobody announced,
  /// without showing it while the pane processes the change, and shows it anew once the change
  /// is over, after any further such changes.
  func takeOverUnannounced(_ result: ResultState) {
    self.result = result
    guard !showsResultAnewSoon else { return }
    showsResultAnewSoon = true
    // The pane's content must stay as it is while its text processes the change.
    Task { @MainActor [weak self] in
      guard let self, let result = self.result else { return }
      showsResultAnewSoon = false
      show(result, anew: true)
      delegate?.presentationDidTakeOverUnannouncedChange(self)
    }
  }

  /// The runs that are collapsed now, in rows of the grid of the panes side by side.
  private var sourceRuns: [CollapsedRun] {
    collapsed.runs.map { CollapsedRun(rows: $0.rows) }
  }

  /// The runs that are collapsed now, in lines of the result, if there is one.
  private var resultRuns: [CollapsedRun] {
    resultRuns(of: collapsed.runs)
  }

  /// The runs that the user expanded and that may collapse again, in rows of the grid of the
  /// panes side by side.
  private var sourceExpandedRuns: [CollapsedRun] {
    collapsed.expandedRuns.map { CollapsedRun(rows: $0.rows) }
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
    return runs.compactMap { run in
      let lines = collapsed.resultLines(of: run, in: result.scrollMap)
      return lines.isEmpty ? nil : CollapsedRun(rows: lines)
    }
  }

  /// Gives every pane the runs that are collapsed now.
  func showCollapsedRuns() {
    let sourceRuns = sourceRuns
    let sourceExpandedRuns = sourceExpandedRuns
    for (_, pane) in layout.sourcePanes {
      pane.collapsedRuns = sourceRuns
      pane.expandedRuns = sourceExpandedRuns
    }
    layout.resultPane?.collapsedRuns = resultRuns
    layout.resultPane?.expandedRuns = resultExpandedRuns
  }

  /// Shows `session`, the same files compared anew, with `result` as the result of a merge,
  /// and keeps the line of B at the reading line where it is.
  ///
  /// The block that holds the first line of the current block in B stays current, or the next
  /// changed block after it; the runs that the user expanded collapse again.
  ///
  /// - Precondition: A merge has a result and a comparison none.
  func show(_ session: Session, result: ResultState?) {
    precondition((result != nil) == arrangement.showsResult, "Only a merge has a result")
    let currentLineOfB = currentBlock.map { changes.blocks[$0].lines(in: .b).lowerBound }
    keepingTheLineOfBInPlace {
      self.result = result
      changes = SessionChanges(session: session, origin: arrangement.origin)
      collapsed = CollapsedRows(session: session, document: result?.document)
      showSession()
    }
    let rowLayout = changes.session.rowLayout
    currentBlock = nil
    setCurrentBlock(
      currentLineOfB.flatMap { line in
        let row = rowLayout.row(ofLine: line, in: .b)
        return changes.blocks.firstIndex { rowLayout.rows(of: $0).upperBound > row }
      })
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
      showSession()
    }
    for pane in allPanes {
      pane.currentBlock = currentBlock
    }
  }

  /// Shows the panes side by side again, after the base came into view or went out of it,
  /// which decides the pane that carries the marks of conflicts.
  func showSourcesAgain() {
    showSession()
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

  /// The row of the grid at `row` of `pane`: the same row in a pane side by side, and the row
  /// that a line of the result lies on.
  func gridRow(ofRow row: Int, in pane: PaneView) -> Int {
    guard pane === layout.resultPane, let result else { return row }
    return result.gridRow(ofLine: row)
  }

  /// The row of `pane` at `gridRow` of the grid: the same row in a pane side by side, and the
  /// line of the result that lies there.
  private func row(ofGridRow gridRow: Int, in pane: PaneView) -> Int {
    guard pane === layout.resultPane, let result else { return gridRow }
    return result.line(ofGridRow: gridRow)
  }

  /// Scrolls `pane` so that `line` of its file, counted from 0, lies at the reading line, and
  /// makes its block current if the line belongs to a changed block; a run that hides the line
  /// expands first.
  ///
  /// - Returns: The row of the line in `pane`.
  @discardableResult
  func go(toLine line: Int, in pane: PaneView) -> Int {
    let rowLayout = changes.session.rowLayout
    let row: Int
    if pane === layout.resultPane {
      row = min(max(line, 0), pane.content.lineNumbers.count - 1)
    } else if let role = layout.sourcePanes.first(where: { $0.pane === pane })?.role {
      let lineCount = rowLayout.lineCount(in: role)
      row = lineCount == 0 ? 0 : rowLayout.row(ofLine: min(max(line, 0), lineCount - 1), in: role)
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
    let place = placeAtReadingLine
    body()
    guard let place, let pane = leadingPane else { return }
    let row = changes.session.rowLayout.row(ofLine: place.lineOfB, in: .b)
    pane.scroll(
      toPlaceRowAtReadingLine: self.row(ofGridRow: row, in: pane), fraction: place.fraction,
      motion: .cut)
  }

  /// The line of B at the reading line of the panes, or the first line after it if a filler row
  /// is there, with how far down its row the reading line passes; `nil` if B has no line from
  /// there on.
  private var placeAtReadingLine: (lineOfB: Int, fraction: CGFloat)? {
    guard let pane = leadingPane else { return nil }
    let (hitRow, fraction) = pane.rowAtReadingLine
    let rowLayout = changes.session.rowLayout
    let row = gridRow(ofRow: hitRow, in: pane)
    guard
      let line = (row..<rowLayout.rowCount).lazy.compactMap({ rowLayout.line(atRow: $0, in: .b) })
        .first
    else { return nil }
    return (line, rowLayout.line(atRow: row, in: .b) == line ? fraction : 0)
  }

  /// Makes `block` current and scrolls it to the reading line of every pane, as far as the text
  /// allows: what every jump of the Go menu does.
  func jump(to block: Int) {
    setCurrentBlock(block)
    let panes = scrollSync.isEnabled ? [leadingPane].compactMap(\.self) : allPanes.filter(\.isShown)
    for pane in panes {
      pane.scroll(
        toPlaceRowAtReadingLine: pane.content.blocks[block].rows.lowerBound, motion: motion)
    }
  }

  /// Brings the current block into view, at the reading line, unless it is in full view already;
  /// how a window shows its first conflict or change when it opens.
  func showCurrentBlock() {
    guard let currentBlock, let pane = leadingPane,
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
