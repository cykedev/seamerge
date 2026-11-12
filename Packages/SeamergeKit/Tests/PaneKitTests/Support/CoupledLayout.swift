import AppKit
import PaneKit

/// The panes of a merge window without the window around them, coupled the way the window
/// couples them: A, base and B side by side, the result below; an overview bar beside B for the
/// three upper panes and one beside the result; the result follows the upper panes block by
/// block.
@MainActor
final class CoupledLayout: NSView {
  let upperPanes: [PaneView]
  let resultPane: PaneView
  let upperBar = OverviewBar()
  let resultBar = OverviewBar()
  let sync = ScrollSync()
  /// The merge as the panes show it, its chunks repeated.
  let merge: SampleMerge
  private let highlightProviders: [SampleHighlights]

  /// Lays out `merge` with `theme`, its chunks `repeats` times over, so that the panes scroll.
  init(merge: SampleMerge, repeats: Int, theme: Theme) {
    let merge = SampleMerge(
      chunks: Array(repeating: merge.chunks, count: repeats).flatMap(\.self),
      ignoredDifferenceRowsOfB: [])
    self.merge = merge
    let contents = SampleMerge.Side.allCases.map { merge.content(of: $0) }
    upperPanes = contents.map { content in
      let pane = PaneView(theme: theme)
      pane.content = content
      return pane
    }
    highlightProviders = [
      SampleHighlights(content: contents[0], reference: contents[1]),
      SampleHighlights(content: contents[1], reference: nil),
      SampleHighlights(content: contents[2], reference: contents[1]),
    ]
    for (pane, provider) in zip(upperPanes, highlightProviders) {
      pane.highlightProvider = provider
    }
    resultPane = PaneView(theme: theme)
    resultPane.content = merge.resultContent()
    super.init(frame: .zero)
    let (upperMarks, resultMarks) = merge.overviewMarks()
    upperBar.theme = theme
    upperBar.marks = upperMarks
    resultBar.theme = theme
    resultBar.marks = resultMarks
    upperPanes[2].overviewBar = upperBar
    resultPane.overviewBar = resultBar
    for pane in upperPanes + [resultPane] {
      addSubview(pane)
      sync.add(pane)
    }
    let anchors = merge.rowAnchors()
    for pane in upperPanes {
      sync.setRowMapping(
        between: pane, and: resultPane,
        forward: { Self.map($0, from: anchors.map(\.upper), to: anchors.map(\.result)) },
        backward: { Self.map($0, from: anchors.map(\.result), to: anchors.map(\.upper)) })
    }
  }

  required init?(coder: NSCoder) {
    nil
  }

  override var isFlipped: Bool { true }

  /// Collapses the long runs of unchanged rows in every pane, except the run at `expanded`, the
  /// way the window does.
  func collapseUnchangedRows(except expanded: Int? = nil) {
    let (upper, result) = merge.collapsedRuns()
    func shown(_ runs: [CollapsedRun]) -> [CollapsedRun] {
      runs.indices.filter { $0 != expanded }.map { runs[$0] }
    }
    for pane in upperPanes {
      pane.collapsedRuns = shown(upper)
    }
    resultPane.collapsedRuns = shown(result)
  }

  /// Makes `block` of the upper panes the current one in every pane and in both bars.
  func setCurrentBlock(_ block: Int) {
    for pane in upperPanes {
      pane.currentBlock = block
    }
    upperBar.currentBlock = block
  }

  override func layout() {
    super.layout()
    let upperHeight = ((bounds.height - Self.hairline) * 0.6).rounded()
    let paneWidth = ((bounds.width - 2 * Self.hairline) / 3).rounded(.down)
    for (index, pane) in upperPanes.enumerated() {
      let x = CGFloat(index) * (paneWidth + Self.hairline)
      let width = index == 2 ? bounds.width - x : paneWidth
      pane.frame = CGRect(x: x, y: 0, width: width, height: upperHeight)
    }
    resultPane.frame = CGRect(
      x: 0, y: upperHeight + Self.hairline, width: bounds.width,
      height: bounds.height - upperHeight - Self.hairline)
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.separatorColor.setFill()
    dirtyRect.fill()
  }

  /// Maps `row` piecewise linearly between matching anchors.
  private static func map(_ row: Double, from sources: [Int], to targets: [Int]) -> Double {
    guard let segment = sources.indices.dropLast().last(where: { Double(sources[$0]) <= row })
    else { return Double(targets.first ?? 0) }
    let start = Double(sources[segment])
    let length = Double(sources[segment + 1]) - start
    let fraction = length > 0 ? min((row - start) / length, 1) : 0
    return Double(targets[segment])
      + fraction * Double(targets[segment + 1] - targets[segment])
  }

  private static let hairline: CGFloat = 1
}

extension SampleMerge {
  /// The first row of every chunk on the grid of the upper panes and in the result, and the end
  /// of both.
  func rowAnchors() -> [(upper: Int, result: Int)] {
    var anchors = [(upper: 0, result: 0)]
    for chunk in chunks {
      let (upper, result) = rowCounts(of: chunk)
      let last = anchors[anchors.count - 1]
      anchors.append((last.upper + upper, last.result + result))
    }
    return anchors
  }

  /// The marks of the bar beside the upper panes, whose blocks they share, and of the bar beside
  /// the result: changes of A on the leading side, of B on the trailing side, conflicts across.
  func overviewMarks() -> (upper: [OverviewMark], result: [OverviewMark]) {
    var upper: [OverviewMark] = []
    var result: [OverviewMark] = []
    var upperRow = 0
    var resultRow = 0
    for chunk in chunks {
      let (upperCount, resultCount) = rowCounts(of: chunk)
      let upperRows = upperRow..<upperRow + upperCount
      let resultRows = resultRow..<resultRow + resultCount
      let block = upper.map(\.block).max().map { $0 + 1 } ?? 0
      let resultBlock = result.map(\.block).max().map { $0 + 1 } ?? 0
      func mark(
        _ rows: Range<Int>, _ style: BlockStyle, _ placement: OverviewMark.Placement, _ block: Int
      ) -> OverviewMark {
        OverviewMark(
          rows: rows, style: style, placement: placement, block: block,
          accessibilityLabel: "Block \(block + 1)")
      }
      switch chunk {
      case .same:
        break
      case .onlyA:
        upper.append(mark(upperRows, .tinted(.a), .leading, block))
        if resultCount > 0 { result.append(mark(resultRows, .tinted(.a), .leading, resultBlock)) }
      case .onlyB:
        upper.append(mark(upperRows, .tinted(.b), .trailing, block))
        if resultCount > 0 { result.append(mark(resultRows, .tinted(.b), .trailing, resultBlock)) }
      case .both:
        upper.append(mark(upperRows, .tinted(.a), .leading, block))
        upper.append(mark(upperRows, .tinted(.b), .trailing, block))
        if resultCount > 0 { result.append(mark(resultRows, .combined, .fullWidth, resultBlock)) }
      case .conflict(_, _, _, _, .open):
        upper.append(mark(upperRows, .tinted(.conflict), .fullWidth, block))
        if resultCount > 0 {
          result.append(mark(resultRows, .tinted(.conflict), .fullWidth, resultBlock))
        }
      case .conflict(_, _, _, _, .handwritten):
        upper.append(mark(upperRows, .handwritten, .fullWidth, block))
        if resultCount > 0 {
          result.append(mark(resultRows, .handwritten, .fullWidth, resultBlock))
        }
      }
      upperRow += upperCount
      resultRow += resultCount
    }
    return (upper, result)
  }

  /// The rows that `chunk` takes on the grid of the upper panes and in the result.
  private func rowCounts(of chunk: Chunk) -> (upper: Int, result: Int) {
    switch chunk {
    case .same(let lines): (lines.count, lines.count)
    case .onlyA(let a, let base, _): (max(a.count, base.count), a.count)
    case .onlyB(let base, let b, _): (max(base.count, b.count), b.count)
    case .both(let a, let base, let b, _): (max(a.count, base.count, b.count), a.count)
    case .conflict(let a, let base, let b, _, .open):
      (max(a.count, base.count, b.count), base.count)
    case .conflict(let a, let base, let b, _, .handwritten(let lines)):
      (max(a.count, base.count, b.count), lines.count)
    }
  }
}
