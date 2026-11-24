import TextBasics

/// The runs of rows of the grid that the panes collapse: long runs of unchanged rows, the same in
/// every pane.
///
/// An unchanged block of at least ``minimumRowCount`` rows collapses, apart from
/// ``contextRowCount`` rows before and after it that stay visible as context; towards the start
/// and the end of the files there is no context. In a merge without a base, the lines that A and
/// B share count as unchanged too. Each pane shows a collapsed run as a bar one row high; where
/// its rows then lie is the pane's affair.
///
/// A run that the user expanded stays expanded until the panes collapse their unchanged rows
/// again. A run never collapses over work in the result: once the segment of its block is
/// edited or chosen, or the insertion point stands in it, it stays expanded.
///
/// In a comparison of the sides of a patch, the row of each placeholder line, ``Session/gapRows``,
/// is a run of its own that stands for the lines the patch passes over: it is always collapsed
/// and never expands. It parts the unchanged rows around it as a changed block would, so that
/// the lines of context of the hunks stay in view.
public struct CollapsedRows: Sendable {
  /// A run of rows of an unchanged block that the panes hide behind a bar.
  public struct Run: Sendable, Hashable {
    /// The unchanged block that the run lies in; in a merge without a base, a block of lines that
    /// A and B share.
    public let block: Block

    /// The rows of the grid that the run hides.
    public let rows: Range<Int>

    /// The number of lines a patch passes over where the run stands for them, or `nil` for a
    /// run of unchanged rows, which expands.
    public let missingLineCount: Int?

    init(block: Block, rows: Range<Int>, missingLineCount: Int? = nil) {
      self.block = block
      self.rows = rows
      self.missingLineCount = missingLineCount
    }
  }

  /// The number of rows from which an unchanged block collapses.
  public static let minimumRowCount = 8

  /// The number of rows that stay visible before and after a collapsed run, unless the run
  /// reaches the start or the end of the files.
  public static let contextRowCount = 3

  /// The grid whose rows collapse.
  public let rowLayout: RowLayout

  /// Whether long runs of unchanged rows collapse; if not, the panes show every row.
  public private(set) var collapsesUnchangedRows: Bool

  /// The runs that are collapsed, in row order.
  public private(set) var runs: [Run] = []

  /// The run that each unchanged block long enough to collapse would hide, in row order.
  private let candidates: [Run]

  /// The runs that stand for lines a patch passes over, in row order.
  private let gaps: [Run]

  /// The blocks whose runs are expanded.
  private var expandedBlocks: Set<Int> = []

  /// The blocks whose runs stay expanded because their segments in the result had work, until
  /// the panes collapse their unchanged rows again.
  private var blocksWithWork: Set<Int> = []

  /// Finds the runs that collapse in the grid of `session`.
  ///
  /// - Parameters:
  ///   - collapsesUnchangedRows: Whether long runs of unchanged rows collapse.
  ///   - document: The result of the merge, whose work keeps runs expanded; `nil` for a
  ///     comparison.
  ///   - caretRow: The row of the insertion point, whose run stays expanded, if any.
  /// - Precondition: `document` is the result of `session`.
  public init(
    session: Session, collapsesUnchangedRows: Bool = true, document: ResultDocument? = nil,
    caretRow: Int? = nil
  ) {
    rowLayout = session.rowLayout
    self.collapsesUnchangedRows = collapsesUnchangedRows
    let rowCount = session.rowLayout.rowCount
    // Without a base, the engine counts the lines that A and B share as a change both made to
    // an empty base; to the user they are unchanged lines like those of a comparison.
    let equalKinds: Set<Block.Kind> =
      session.kind == .merge && session.files.base == nil
      ? [.unchanged, .changedInBoth] : [.unchanged]
    let gaps = session.gapRows.map { gap in
      Run(
        block: session.rowLayout.block(atRow: gap.row), rows: gap.row..<gap.row + 1,
        missingLineCount: gap.lineCount)
    }
    self.gaps = gaps
    let gapStarts = gaps.map(\.rows.lowerBound)
    candidates = session.blocks.flatMap { block -> [Run] in
      guard equalKinds.contains(block.kind) else { return [] }
      return Self.parts(of: session.rowLayout.rows(of: block), apartFrom: gapStarts).compactMap {
        rows in
        guard rows.count >= Self.minimumRowCount else { return nil }
        let start = rows.lowerBound == 0 ? 0 : rows.lowerBound + Self.contextRowCount
        let end = rows.upperBound == rowCount ? rowCount : rows.upperBound - Self.contextRowCount
        return Run(block: block, rows: start..<end)
      }
    }
    blocksWithWork = document.map { Self.blocks(withWorkIn: $0, candidates: candidates) } ?? []
    expandedBlocks = blocksWithWork
    if collapsesUnchangedRows, let caretRow,
      let run = Self.run(in: candidates, containingRow: caretRow)
    {
      expandedBlocks.insert(run.block.id)
    }
    update()
  }

  /// The collapsed run that hides `row`, if any.
  public func run(containingRow row: Int) -> Run? {
    Self.run(in: runs, containingRow: row)
  }

  /// The runs that are expanded while the panes collapse their unchanged rows and that may
  /// collapse again on their own, in row order: those without work in the result.
  public var expandedRuns: [Run] {
    guard collapsesUnchangedRows else { return [] }
    return candidates.filter {
      expandedBlocks.contains($0.block.id) && !blocksWithWork.contains($0.block.id)
    }
  }

  /// The lines of the result that `run` hides, so that the result pane collapses them too.
  ///
  /// The segment of an unchanged block that is neither edited nor chosen holds the lines of its
  /// block one for one, so the run hides as many lines of the result as rows of the grid.
  ///
  /// - Parameter map: The scroll map of the result as it is now.
  public func resultLines(of run: Run, in map: ScrollMap) -> Range<Int> {
    let blockStart = rowLayout.rows(of: run.block).lowerBound
    let offset = Int(map.targetPosition(at: Double(blockStart)).rounded()) - blockStart
    return run.rows.lowerBound + offset..<run.rows.upperBound + offset
  }

  /// The lines of the input of `role` that `run` hides, so that a pane without filler rows
  /// collapses them too.
  ///
  /// An unchanged block has the same lines in every input, so the run hides as many lines of
  /// each as rows of the grid.
  ///
  /// - Precondition: The input of `role` takes part in the session.
  public func lines(of run: Run, in role: Role) -> Range<Int> {
    let offset = run.block.lines(in: role).lowerBound - rowLayout.rows(of: run.block).lowerBound
    return run.rows.lowerBound + offset..<run.rows.upperBound + offset
  }

  /// Expands `run`, which then stays expanded until ``collapseUnchangedRows(document:caretRow:)``
  /// or ``collapse(_:)``; a run that stands for lines a patch passes over stays as it is.
  public mutating func expand(_ run: Run) {
    guard run.missingLineCount == nil, expandedBlocks.insert(run.block.id).inserted else { return }
    update()
  }

  /// Collapses `run` again, one of the ``expandedRuns``; a run with work in the result stays
  /// expanded.
  ///
  /// - Returns: Whether the run collapsed.
  @discardableResult
  public mutating func collapse(_ run: Run) -> Bool {
    guard expandedRuns.contains(run) else { return false }
    expandedBlocks.remove(run.block.id)
    update()
    return true
  }

  /// Expands the run that hides `row`, so that a target there, such as a match of a search or a
  /// jump, comes into view.
  ///
  /// - Returns: Whether a run was expanded.
  @discardableResult
  public mutating func expandToShow(row: Int) -> Bool {
    guard let run = run(containingRow: row), run.missingLineCount == nil else { return false }
    expand(run)
    return true
  }

  /// Expands the run that hides a line of the input of `role`, such as the target of Go to Line.
  ///
  /// - Returns: Whether a run was expanded.
  /// - Precondition: `line` lies within `0..<rowLayout.lineCount(in: role)`.
  @discardableResult
  public mutating func expandToShow(line: Int, in role: Role) -> Bool {
    expandToShow(row: rowLayout.row(ofLine: line, in: role))
  }

  /// Keeps the runs expanded whose segments in `document` are edited or chosen; called after
  /// each change of the result.
  ///
  /// A run stays expanded once its segment has had work, also after that work is undone, so that
  /// rows do not vanish while the user looks at them.
  ///
  /// - Precondition: `document` is the result of the session that the runs were found in.
  public mutating func keepWorkExpanded(in document: ResultDocument) {
    let work = Self.blocks(withWorkIn: document, candidates: candidates)
    blocksWithWork.formUnion(work)
    guard !work.isSubset(of: expandedBlocks) else { return }
    expandedBlocks.formUnion(work)
    update()
  }

  /// Shows every row: Show All Lines.
  public mutating func showAllRows() {
    guard collapsesUnchangedRows else { return }
    collapsesUnchangedRows = false
    update()
  }

  /// Collapses every long run of unchanged rows again, except those with work in the result and
  /// the run of the insertion point: Collapse Unchanged Lines.
  ///
  /// - Parameters:
  ///   - document: The result of the merge; `nil` for a comparison.
  ///   - caretRow: The row of the insertion point, if any.
  /// - Precondition: `document` is the result of the session that the runs were found in.
  public mutating func collapseUnchangedRows(document: ResultDocument?, caretRow: Int?) {
    collapsesUnchangedRows = true
    blocksWithWork = document.map { Self.blocks(withWorkIn: $0, candidates: candidates) } ?? []
    expandedBlocks = blocksWithWork
    if let caretRow, let run = Self.run(in: candidates, containingRow: caretRow) {
      expandedBlocks.insert(run.block.id)
    }
    update()
  }

  /// Collapses the candidates that are not expanded, beside the runs of lines a patch passes
  /// over.
  private mutating func update() {
    let collapsed =
      collapsesUnchangedRows ? candidates.filter { !expandedBlocks.contains($0.block.id) } : []
    runs =
      gaps.isEmpty
      ? collapsed : (collapsed + gaps).sorted { $0.rows.lowerBound < $1.rows.lowerBound }
  }

  /// The parts of `rows`, the rows of an unchanged block, between the rows that start at
  /// `gapStarts`, which are in ascending order.
  private static func parts(of rows: Range<Int>, apartFrom gapStarts: [Int]) -> [Range<Int>] {
    var parts: [Range<Int>] = []
    var start = rows.lowerBound
    let first = gapStarts.partitioningIndex { $0 >= rows.lowerBound }
    for gap in gapStarts[first...].prefix(while: { $0 < rows.upperBound }) {
      parts.append(start..<gap)
      start = gap + 1
    }
    parts.append(start..<rows.upperBound)
    return parts
  }

  /// The blocks among `candidates` whose segments in `document` hold work: an edit or a choice.
  private static func blocks(withWorkIn document: ResultDocument, candidates: [Run]) -> Set<Int> {
    Set(
      candidates.lazy.map(\.block).filter {
        [.chosen, .edited].contains(document.segment(for: $0).state)
      }.map(\.id))
  }

  /// The run among `runs`, which are in row order, that holds `row`, if any.
  private static func run(in runs: [Run], containingRow row: Int) -> Run? {
    guard let index = lastIndex(in: runs.indices, where: { runs[$0].rows.lowerBound <= row }),
      runs[index].rows.contains(row)
    else { return nil }
    return runs[index]
  }

  /// The last index in `indices` for which `isAtOrBefore` holds, or `nil` if it holds for none,
  /// given that once it fails, it fails for every later index.
  private static func lastIndex(
    in indices: Range<Int>, where isAtOrBefore: (Int) -> Bool
  ) -> Int? {
    let end = indices.partitioningIndex { !isAtOrBefore($0) }
    return end > indices.lowerBound ? end - 1 : nil
  }
}
