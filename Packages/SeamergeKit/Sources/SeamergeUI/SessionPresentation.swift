import AppKit
import MergeModel
import PaneKit

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

  /// The accessibility settings, of which the presentation reads whether movement is reduced.
  var displayOptions: DisplayOptions {
    didSet { decisionColumn?.reducesMotion = displayOptions.reducesMotion }
  }

  private let layout: SessionSplitViewController
  private let headers: [Role: SideHeader]
  private var collapsed: CollapsedRows
  private var highlights: [BlockHighlights] = []

  /// Shows `session` in the panes of `layout`, arranged as `arrangement` says: a merge as
  /// loaded, every conflict open and every other change taken as the merge takes it, with the
  /// first open conflict current, or the first change if no conflict is open.
  ///
  /// - Parameters:
  ///   - headers: The headers of the inputs, whose names the panes take for VoiceOver.
  ///   - resultHeader: The header of the result, if there is one.
  init(
    session: Session, arrangement: PaneArrangement, layout: SessionSplitViewController,
    headers: [Role: SideHeader], resultHeader: ResultHeader?, displayOptions: DisplayOptions
  ) {
    let result = arrangement.showsResult ? ResultState(session: session) : nil
    self.arrangement = arrangement
    self.layout = layout
    self.headers = headers
    self.displayOptions = displayOptions
    self.result = result
    changes = SessionChanges(session: session, origin: arrangement.origin)
    collapsed = CollapsedRows(session: session, document: result?.document)
    resultOverviewBar = layout.resultPane.map { _ in OverviewBar() }
    decisionColumn = layout.resultPane.map { _ in DecisionColumnView() }

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
    decisionColumn?.reducesMotion = displayOptions.reducesMotion
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
    showSession()
    setCurrentBlock(navigation.firstOpenConflict ?? navigation.firstChange)
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
    }
    sourcesOverviewBar.marks = OverviewMarks.sources(
      of: changes, document: result?.document, arrangement: arrangement)
    guard let result, let resultPane = layout.resultPane else { return }
    let content = ResultPaneContent(
      document: result.document, text: result.text, changes: changes, headers: headers)
    resultPane.setContent(content.content, collapsedRuns: resultRuns)
    resultOverviewBar?.marks = OverviewMarks.result(
      of: changes, document: result.document, result: content.content)
    decisionColumn?.decisions = content.decisions
  }

  /// The runs that are collapsed now, in rows of the grid of the panes side by side.
  private var sourceRuns: [CollapsedRun] {
    collapsed.runs.map { CollapsedRun(rows: $0.rows) }
  }

  /// The runs that are collapsed now, in lines of the result, if there is one.
  private var resultRuns: [CollapsedRun] {
    guard let result else { return [] }
    return collapsed.runs.compactMap { run in
      let lines = collapsed.resultLines(of: run, in: result.scrollMap)
      return lines.isEmpty ? nil : CollapsedRun(rows: lines)
    }
  }

  /// Gives every pane the runs that are collapsed now.
  private func showCollapsedRuns() {
    let sourceRuns = sourceRuns
    for (_, pane) in layout.sourcePanes {
      pane.collapsedRuns = sourceRuns
    }
    layout.resultPane?.collapsedRuns = resultRuns
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

  /// Whether long runs of unchanged rows are collapsed.
  var collapsesUnchangedRows: Bool {
    collapsed.collapsesUnchangedRows
  }

  /// Whether Show All Lines or Collapse Unchanged Lines would change what the panes show: there
  /// are collapsed runs to show, or runs to collapse, leaving out the one of the line
  /// `caretLine` of the result if the insertion point is there.
  func canToggleCollapsedRows(caretLine: Int?) -> Bool {
    if collapsed.collapsesUnchangedRows {
      return !collapsed.runs.isEmpty
    }
    var collapsing = collapsed
    collapsing.collapseUnchangedRows(
      document: result?.document, caretRow: caretRow(ofLine: caretLine))
    return !collapsing.runs.isEmpty
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
  private func gridRow(ofRow row: Int, in pane: PaneView) -> Int {
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
  private func select(_ hit: PaneHit, in pane: PaneView) {
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

  /// How the panes move when they scroll to a block.
  private var motion: PaneView.ScrollMotion {
    displayOptions.reducesMotion ? .cut : .glideWithinAWindowHeight
  }
}

/// Learns what changes in a presentation and supplies what it shows on demand.
@MainActor
protocol SessionPresentationDelegate: AnyObject {
  /// Tells the delegate that another block became current, or none.
  func presentationDidChangeCurrentBlock(_ presentation: SessionPresentation)

  /// The context menu for a secondary click on `hit` in `pane`.
  func presentation(
    _ presentation: SessionPresentation, menuFor hit: PaneHit, in pane: PaneView
  ) -> NSMenu
}

extension SessionPresentation: PaneViewDelegate {
  /// A click on a row of a changed block makes the block current; the click still places the
  /// insertion point and selects text as in any text.
  func pane(_ pane: PaneView, didClick hit: PaneHit) {
    select(hit, in: pane)
  }

  /// A secondary click first makes the block under the pointer current, as a click does, then
  /// shows the menu of the delegate in place of the text view's standard one, which holds
  /// commands that do not apply to a session.
  func pane(_ pane: PaneView, menuFor hit: PaneHit) -> NSMenu? {
    select(hit, in: pane)
    return delegate?.presentation(self, menuFor: hit, in: pane)
  }

  /// Expands the run in every pane that shows it.
  func pane(_ pane: PaneView, didAskToExpand run: CollapsedRun) {
    let row = gridRow(ofRow: run.rows.lowerBound, in: pane)
    guard let collapsedRun = collapsed.run(containingRow: row) else { return }
    collapsed.expand(collapsedRun)
    showCollapsedRuns()
  }
}

extension SessionPresentation: OverviewBarDelegate {
  /// A click on a mark makes its block current; the bar scrolls to it on its own.
  func overviewBar(_ overviewBar: OverviewBar, didSelectBlock block: Int) {
    setCurrentBlock(block)
  }
}

extension SessionPresentation: DecisionColumnDelegate {
  /// The result is read-only, so a toggle shows how a block came by its text but changes nothing.
  func decisionColumn(
    _ column: DecisionColumnView, didSwitchToggle toggle: Int, ofBlock block: Int
  ) {}

  /// The result is read-only, so every block stays as it was loaded.
  func decisionColumn(_ column: DecisionColumnView, didAskToResetBlock block: Int) {}

  /// A click beside a block makes it current, as a click on its rows does.
  func decisionColumn(_ column: DecisionColumnView, didClickBlock block: Int) {
    guard let resultPane = layout.resultPane else { return }
    select(
      PaneHit(row: resultPane.content.blocks[block].rows.lowerBound, block: block), in: resultPane)
  }
}
