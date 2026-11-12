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
          source: role, of: changes, document: document, ignoredDifferences: ignoredDifferences),
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

extension MergePresentation: PaneViewDelegate {
  /// A click on a row of a changed block makes the block current; the click still places the
  /// insertion point and selects text as in any text.
  func pane(_ pane: PaneView, didClick hit: PaneHit) {
    select(hit, in: pane)
  }

  /// The panes offer no context menu of their own, nor the text view's standard one, which holds
  /// commands that do not apply to a merge.
  func pane(_ pane: PaneView, menuFor hit: PaneHit) -> NSMenu? {
    nil
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
