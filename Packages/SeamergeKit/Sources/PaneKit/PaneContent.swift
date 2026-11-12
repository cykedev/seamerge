import Foundation

/// What a pane shows: its rows on the grid, the line number of each row and the blocks.
///
/// Row *r* is paragraph *r* of the text, so panes with the same number of rows have the same
/// height and their rows line up.
public struct PaneContent: Sendable {
  /// The text of the rows, separated by line feeds.
  public var text: String

  /// The zero-based number of the line that each row shows, or -1 for a filler row.
  public var lineNumbers: [Int32]

  /// The blocks, in row order and without overlap.
  ///
  /// Rows outside every block are unchanged.
  public var blocks: [PaneBlock]

  /// The rows whose line differs from the line it is compared with, although the comparison
  /// counts both as equal.
  public var ignoredDifferenceRows: IndexSet

  /// How the line of each row ends in the file, shown among the invisible characters.
  public var lineEndings: [LineEnding]

  /// Creates the content of a pane.
  ///
  /// Without `lineEndings`, every row that shows a line ends with a line feed, except the last
  /// row, which has no ending.
  ///
  /// - Precondition: `lineNumbers` and `lineEndings` have one entry per row of `text`, and the
  ///   blocks are sorted, do not overlap and lie within the rows.
  public init(
    text: String, lineNumbers: [Int32], blocks: [PaneBlock] = [],
    ignoredDifferenceRows: IndexSet = [], lineEndings: [LineEnding]? = nil
  ) {
    self.text = text
    self.lineNumbers = lineNumbers
    self.blocks = blocks
    self.ignoredDifferenceRows = ignoredDifferenceRows
    self.lineEndings =
      lineEndings
      ?? lineNumbers.indices.map { row in
        lineNumbers[row] < 0 || row == lineNumbers.count - 1 ? .none : .lineFeed
      }
  }

  /// A pane without text.
  public static let empty = PaneContent(text: "", lineNumbers: [-1])

  /// The index of the block that `row` belongs to, or `nil` if the row is unchanged.
  func blockIndex(atRow row: Int) -> Int? {
    var low = 0
    var high = blocks.count
    while low < high {
      let middle = (low + high) / 2
      if blocks[middle].rows.upperBound <= row {
        low = middle + 1
      } else {
        high = middle
      }
    }
    guard low < blocks.count, blocks[low].rows.contains(row) else { return nil }
    return low
  }

  /// Whether `row` is a filler row, which shows no line of the file.
  func isFiller(row: Int) -> Bool {
    lineNumbers[row] < 0
  }

  /// How the lines end that an edit breaks into rows of their own: like the line the break was
  /// typed in, or the line before it where that one has no ending; without either, like most
  /// lines of the content, and with a line feed if no line has an ending.
  private func newLineEnding(for change: RowChange) -> LineEnding {
    let first = change.oldRows.lowerBound
    for row in [first, first - 1] where lineEndings.indices.contains(row) {
      if lineEndings[row] != .none { return lineEndings[row] }
    }
    var counts: [LineEnding: Int] = [:]
    for ending in lineEndings where ending != .none {
      counts[ending, default: 0] += 1
    }
    return counts.max { $0.value < $1.value }?.key ?? .lineFeed
  }

  /// Takes over an edit of the text, now `text`, that rewrote rows as `change` says.
  ///
  /// The rewritten rows show lines of their own, numbered on from the line before them, and the
  /// lines after them follow on. Blocks keep their rows as ``RowChange`` maps them. The owner of
  /// the content gives the pane the exact blocks afterwards; until then, this keeps every row
  /// described.
  mutating func takeOver(_ change: RowChange, text: String) {
    self.text = text
    let ending = lineEndings[change.oldRows.upperBound - 1]
    lineEndings.replaceSubrange(
      change.oldRows,
      with: Array(repeating: newLineEnding(for: change), count: change.newRows.count - 1)
        + [ending])
    lineNumbers.replaceSubrange(
      change.oldRows, with: Array(repeating: 0, count: change.newRows.count))
    var next = (lineNumbers[..<change.newRows.lowerBound].last { $0 >= 0 } ?? -1) + 1
    for row in change.newRows.lowerBound..<lineNumbers.count
    where change.newRows.contains(row) || lineNumbers[row] >= 0 {
      lineNumbers[row] = next
      next += 1
    }
    for index in blocks.indices {
      blocks[index].rows = change.newRows(of: blocks[index].rows)
    }
    ignoredDifferenceRows = IndexSet(
      ignoredDifferenceRows.compactMap { row in
        change.oldRows.contains(row) ? nil : change.newBoundary(of: row)
      })
  }
}

/// A run of rows that changed on at least one side, as one pane shows it.
public struct PaneBlock: Sendable, Hashable {
  /// The rows of the block on the grid.
  public var rows: Range<Int>

  /// How the rows are tinted.
  public var style: BlockStyle

  /// How this pane's side changed the block, or `nil` if it did not.
  public var marker: Marker?

  /// The mark of a conflict, shown on the base pane, or on B while the base is hidden.
  public var conflict: ConflictMarker?

  /// Creates a block.
  public init(
    rows: Range<Int>, style: BlockStyle, marker: Marker? = nil, conflict: ConflictMarker? = nil
  ) {
    self.rows = rows
    self.style = style
    self.marker = marker
    self.conflict = conflict
  }
}
