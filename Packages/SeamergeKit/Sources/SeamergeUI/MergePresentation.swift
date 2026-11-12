import AppKit
import MergeModel
import PaneKit

/// Shows a merge in the panes of a window: what each pane shows, the marks of the overview bars,
/// the signs of the decision column, the collapsed runs of unchanged rows, the current block, and
/// the coupling that keeps the panes at the same place while one of them scrolls.
@MainActor
final class MergePresentation {
  /// The changed blocks, as every pane numbers them.
  private(set) var changes: SessionChanges

  /// The result as the panes show it.
  private(set) var document: ResultDocument

  /// The text of the result, as long as the segments of the document together.
  private(set) var resultText: String

  /// The index of the current block among the changed blocks, or `nil` if there is none.
  ///
  /// Every pane tints the current block more strongly and the overview bars point at it.
  private(set) var currentBlock: Int?

  /// The bar beside the panes above the result, which is their scroller.
  let sourcesOverviewBar = OverviewBar()

  /// The bar beside the result, which is its scroller.
  let resultOverviewBar = OverviewBar()

  /// The decision column beside the result.
  let decisionColumn = DecisionColumnView()

  /// The coupling of the panes, which keeps them at the same place while one of them scrolls.
  let scrollSync = ScrollSync()

  /// Learns when the current block changes and supplies the context menus of the panes; the
  /// presentation does not retain it.
  weak var delegate: (any MergePresentationDelegate)?

  /// The accessibility settings, of which the presentation reads whether movement is reduced.
  var displayOptions: DisplayOptions

  private let layout: SessionSplitViewController
  private let headers: [Role: SideHeader]
  private var collapsed: CollapsedRows
  private var scrollMap: ScrollMap
  private var highlights: [BlockHighlights] = []

  /// Shows `session` in the panes of `layout`, as loaded: every conflict open, every other change
  /// taken as the merge takes it, and the first open conflict current, or the first change if no
  /// conflict is open.
  ///
  /// - Parameter headers: The headers of the inputs, whose names the panes take for VoiceOver.
  init(
    session: Session, layout: SessionSplitViewController, headers: [Role: SideHeader],
    resultHeader: ResultHeader, displayOptions: DisplayOptions
  ) {
    let document = ResultDocument(session: session)
    self.layout = layout
    self.headers = headers
    self.displayOptions = displayOptions
    self.document = document
    resultText = document.initialText
    changes = SessionChanges(session: session)
    collapsed = CollapsedRows(session: session, document: document)
    scrollMap = ScrollMap(document: document, text: resultText)

    for (role, pane) in layout.sourcePanes {
      pane.setAccessibilityLabel(headers[role]?.spokenName)
    }
    layout.resultPane.setAccessibilityLabel(resultHeader.spokenName)
    let theme = displayOptions.theme
    for bar in [sourcesOverviewBar, resultOverviewBar] {
      bar.theme = theme
      bar.delegate = self
    }
    layout.sourcePanes.last?.pane.overviewBar = sourcesOverviewBar
    layout.resultPane.overviewBar = resultOverviewBar
    decisionColumn.theme = theme
    decisionColumn.delegate = self
    layout.resultPane.decisionColumn = decisionColumn
    for pane in allPanes {
      scrollSync.add(pane)
      pane.delegate = self
    }
    for (_, pane) in layout.sourcePanes {
      scrollSync.setRowMapping(
        between: layout.resultPane, and: pane,
        forward: { [weak self] line in self?.scrollMap.row(atResultLine: line) ?? line },
        backward: { [weak self] row in self?.scrollMap.resultLine(atRow: row) ?? row })
    }
    showDocument()
    setCurrentBlock(navigation.firstOpenConflict ?? navigation.firstChange)
  }

  /// Draws the overview bars and the decision column with `theme`.
  func apply(_ theme: Theme) {
    sourcesOverviewBar.theme = theme
    resultOverviewBar.theme = theme
    decisionColumn.theme = theme
  }

  /// Every pane: the inputs, then the result.
  var allPanes: [PaneView] {
    layout.sourcePanes.map(\.pane) + [layout.resultPane]
  }

  /// Where the current block lies among the changed blocks, and where the others lie.
  var navigation: BlockNavigation {
    BlockNavigation(
      isOpenConflict: changes.blocks.map { document.segment(for: $0).state == .open },
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
    resultOverviewBar.currentBlock = block
    delegate?.presentationDidChangeCurrentBlock(self)
  }

  /// Shows the document in every pane: the contents, the collapsed runs, the marks of the
  /// overview bars and the signs of the decision column.
  private func showDocument() {
    let ignoredDifferences = IgnoredDifferences(in: changes.session)
    let sourceRuns = sourceRuns
    highlights = []
    for (role, pane) in layout.sourcePanes {
      let provider = BlockHighlights(changes: changes, role: role)
      highlights.append(provider)
      pane.highlightProvider = provider
      pane.setContent(
        PaneContent(
          source: role, of: changes, document: document, ignoredDifferences: ignoredDifferences,
          conflictMarkRole: changes.conflictMarkRole(baseIsShown: layout.showsBase)),
        collapsedRuns: sourceRuns)
    }
    let result = ResultPaneContent(
      document: document, text: resultText, changes: changes, headers: headers)
    layout.resultPane.setContent(result.content, collapsedRuns: resultRuns)
    sourcesOverviewBar.marks = OverviewMarks.sources(of: changes, document: document)
    resultOverviewBar.marks = OverviewMarks.result(
      of: changes, document: document, result: result.content)
    decisionColumn.decisions = result.decisions
  }

  /// The runs that are collapsed now, in rows of the grid of the panes above.
  private var sourceRuns: [CollapsedRun] {
    collapsed.runs.map { CollapsedRun(rows: $0.rows) }
  }

  /// The runs that are collapsed now, in lines of the result.
  private var resultRuns: [CollapsedRun] {
    collapsed.runs.compactMap { run in
      let lines = collapsed.resultLines(of: run, in: scrollMap)
      return lines.isEmpty ? nil : CollapsedRun(rows: lines)
    }
  }

  /// Gives every pane the runs that are collapsed now.
  private func showCollapsedRuns() {
    let sourceRuns = sourceRuns
    for (_, pane) in layout.sourcePanes {
      pane.collapsedRuns = sourceRuns
    }
    layout.resultPane.collapsedRuns = resultRuns
  }

  /// Shows `document`, a result of the same files with another comparison, whose text is
  /// `text`, and keeps the line of B at the reading line where it is.
  ///
  /// The block that holds the first line of the current block in B stays current, or the next
  /// changed block after it; the runs that the user expanded collapse again.
  func show(_ document: ResultDocument, text: String) {
    let currentLineOfB = currentBlock.map { changes.blocks[$0].lines(in: .b).lowerBound }
    keepingTheLineOfBInPlace {
      self.document = document
      resultText = text
      changes = SessionChanges(session: document.session)
      collapsed = CollapsedRows(session: document.session, document: document)
      scrollMap = ScrollMap(document: document, text: text)
      showDocument()
    }
    let rowLayout = changes.session.rowLayout
    currentBlock = nil
    setCurrentBlock(
      currentLineOfB.flatMap { line in
        let row = rowLayout.row(ofLine: line, in: .b)
        return changes.blocks.firstIndex { rowLayout.rows(of: $0).upperBound > row }
      })
  }

  /// Shows the panes above the result again, after the base came into view or went out of it,
  /// which decides the pane that carries the marks of conflicts.
  func showSourcesAgain() {
    showDocument()
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
    collapsing.collapseUnchangedRows(document: document, caretRow: caretRow(ofLine: caretLine))
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
    collapsed.collapseUnchangedRows(document: document, caretRow: caretRow(ofLine: caretLine))
    showCollapsedRuns()
  }

  /// The row of the grid of line `line` of the result.
  private func caretRow(ofLine line: Int?) -> Int? {
    line.map { Int(scrollMap.row(atResultLine: Double($0)).rounded(.down)) }
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
    let gridRow: Int
    if pane === layout.resultPane {
      row = min(max(line, 0), pane.content.lineNumbers.count - 1)
      gridRow = Int(scrollMap.row(atResultLine: Double(row)).rounded(.down))
    } else if let role = layout.sourcePanes.first(where: { $0.pane === pane })?.role {
      let lineCount = rowLayout.lineCount(in: role)
      gridRow =
        lineCount == 0 ? 0 : rowLayout.row(ofLine: min(max(line, 0), lineCount - 1), in: role)
      row = gridRow
    } else {
      return 0
    }
    if collapsed.expandToShow(row: gridRow) {
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
    let leadingRow =
      pane === layout.resultPane ? Int(scrollMap.resultLine(atRow: Double(row))) : row
    pane.scroll(toPlaceRowAtReadingLine: leadingRow, fraction: place.fraction, motion: .cut)
  }

  /// The line of B at the reading line of the panes, or the first line after it if a filler row
  /// is there, with how far down its row the reading line passes; `nil` if B has no line from
  /// there on.
  private var placeAtReadingLine: (lineOfB: Int, fraction: CGFloat)? {
    guard let pane = leadingPane else { return nil }
    let (hitRow, fraction) = pane.rowAtReadingLine
    let rowLayout = changes.session.rowLayout
    let row =
      pane === layout.resultPane
      ? Int(scrollMap.row(atResultLine: Double(hitRow)).rounded(.down)) : hitRow
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
  /// how a window shows its first conflict when it opens.
  func showCurrentBlock() {
    guard let currentBlock, let pane = leadingPane,
      !pane.showsWhole(rows: pane.content.blocks[currentBlock].rows)
    else { return }
    pane.scroll(
      toPlaceRowAtReadingLine: pane.content.blocks[currentBlock].rows.lowerBound, motion: .cut)
  }

  /// The pane that the others follow when the window scrolls to a block: the first source pane
  /// in view, or the result while the sources are out of view.
  var leadingPane: PaneView? {
    layout.sourcePanes.map(\.pane).first(where: \.isShown)
      ?? (layout.resultPane.isShown ? layout.resultPane : nil)
  }

  /// Makes the block of `hit` in `pane` current, if the hit lies in a changed block, and brings
  /// it into view in the other area, unless it is in full view there already.
  private func select(_ hit: PaneHit, in pane: PaneView) {
    guard let block = hit.block else { return }
    setCurrentBlock(block)
    let others = pane === layout.resultPane ? layout.sourcePanes.map(\.pane) : [layout.resultPane]
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
protocol MergePresentationDelegate: AnyObject {
  /// Tells the delegate that another block became current, or none.
  func presentationDidChangeCurrentBlock(_ presentation: MergePresentation)

  /// The context menu for a secondary click on `hit` in `pane`.
  func presentation(_ presentation: MergePresentation, menuFor hit: PaneHit, in pane: PaneView)
    -> NSMenu
}

extension MergePresentation: PaneViewDelegate {
  /// A click on a row of a changed block makes the block current; the click still places the
  /// insertion point and selects text as in any text.
  func pane(_ pane: PaneView, didClick hit: PaneHit) {
    select(hit, in: pane)
  }

  /// A secondary click first makes the block under the pointer current, as a click does, then
  /// shows the menu of the delegate in place of the text view's standard one, which holds
  /// commands that do not apply to a merge.
  func pane(_ pane: PaneView, menuFor hit: PaneHit) -> NSMenu? {
    select(hit, in: pane)
    return delegate?.presentation(self, menuFor: hit, in: pane)
  }

  /// Expands the run in every pane that shows it.
  func pane(_ pane: PaneView, didAskToExpand run: CollapsedRun) {
    let row =
      pane === layout.resultPane
      ? Int(scrollMap.row(atResultLine: Double(run.rows.lowerBound)).rounded(.down))
      : run.rows.lowerBound
    guard let collapsedRun = collapsed.run(containingRow: row) else { return }
    collapsed.expand(collapsedRun)
    showCollapsedRuns()
  }
}

extension MergePresentation: OverviewBarDelegate {
  /// A click on a mark makes its block current; the bar scrolls to it on its own.
  func overviewBar(_ overviewBar: OverviewBar, didSelectBlock block: Int) {
    setCurrentBlock(block)
  }
}

extension MergePresentation: DecisionColumnDelegate {
  /// The result is read-only, so a toggle shows how a block came by its text but changes nothing.
  func decisionColumn(
    _ column: DecisionColumnView, didSwitchToggle toggle: Int, ofBlock block: Int
  ) {}

  /// The result is read-only, so every block stays as it was loaded.
  func decisionColumn(_ column: DecisionColumnView, didAskToResetBlock block: Int) {}

  /// A click beside a block makes it current, as a click on its rows does.
  func decisionColumn(_ column: DecisionColumnView, didClickBlock block: Int) {
    select(
      PaneHit(row: layout.resultPane.content.blocks[block].rows.lowerBound, block: block),
      in: layout.resultPane)
  }
}
