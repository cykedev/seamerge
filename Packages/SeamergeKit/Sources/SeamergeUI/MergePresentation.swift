import AppKit
import MergeModel
import PaneKit

/// Shows a merge in the panes of a window: what each pane shows, the marks of the overview bars,
/// the signs of the decision column, the collapsed runs of unchanged rows, and the coupling that
/// keeps the panes at the same place while one of them scrolls.
@MainActor
final class MergePresentation {
  /// The changed blocks, as every pane numbers them.
  let changes: SessionChanges

  /// The bar beside the panes above the result, which is their scroller.
  let sourcesOverviewBar = OverviewBar()

  /// The bar beside the result, which is its scroller.
  let resultOverviewBar = OverviewBar()

  /// The decision column beside the result.
  let decisionColumn = DecisionColumnView()

  private let layout: SessionSplitViewController
  private let scrollSync = ScrollSync()
  private var collapsed: CollapsedRows
  private let scrollMap: ScrollMap
  private var highlights: [BlockHighlights] = []

  /// Shows `session` in the panes of `layout`.
  ///
  /// - Parameter headers: The headers of the inputs, whose names the panes take for VoiceOver.
  init(
    session: Session, layout: SessionSplitViewController, headers: [Role: SideHeader],
    resultHeader: ResultHeader, theme: Theme
  ) {
    let document = ResultDocument(session: session)
    let changes = SessionChanges(session: session)
    let text = document.initialText
    self.changes = changes
    self.layout = layout
    collapsed = CollapsedRows(session: session, document: document)
    scrollMap = ScrollMap(document: document, text: text)

    let ignoredDifferences = IgnoredDifferences(in: session)
    let sourceRuns = sourceRuns
    let resultRuns = resultRuns
    for (role, pane) in layout.sourcePanes {
      let provider = BlockHighlights(changes: changes, role: role)
      highlights.append(provider)
      pane.highlightProvider = provider
      pane.setContent(
        PaneContent(
          source: role, of: changes, document: document, ignoredDifferences: ignoredDifferences),
        collapsedRuns: sourceRuns)
      pane.setAccessibilityLabel(headers[role]?.spokenName)
    }
    let result = ResultPaneContent(
      document: document, text: text, changes: changes, headers: headers)
    layout.resultPane.setContent(result.content, collapsedRuns: resultRuns)
    layout.resultPane.setAccessibilityLabel(resultHeader.spokenName)

    for bar in [sourcesOverviewBar, resultOverviewBar] {
      bar.theme = theme
    }
    sourcesOverviewBar.marks = OverviewMarks.sources(of: changes, document: document)
    resultOverviewBar.marks = OverviewMarks.result(
      of: changes, document: document, result: result.content)
    layout.sourcePanes.last?.pane.overviewBar = sourcesOverviewBar
    layout.resultPane.overviewBar = resultOverviewBar
    decisionColumn.theme = theme
    decisionColumn.decisions = result.decisions
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
  }

  /// Draws the overview bars and the decision column with `theme`.
  func apply(_ theme: Theme) {
    sourcesOverviewBar.theme = theme
    resultOverviewBar.theme = theme
    decisionColumn.theme = theme
  }

  /// Every pane: the inputs, then the result.
  private var allPanes: [PaneView] {
    layout.sourcePanes.map(\.pane) + [layout.resultPane]
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
}

extension MergePresentation: PaneViewDelegate {
  /// Clicks only place the insertion point and select text; they leave the current block alone.
  func pane(_ pane: PaneView, didClick hit: PaneHit) {}

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
    let sourceRuns = sourceRuns
    for (_, pane) in layout.sourcePanes {
      pane.collapsedRuns = sourceRuns
    }
    layout.resultPane.collapsedRuns = resultRuns
  }
}
