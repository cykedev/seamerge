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

  /// The places within the rows of ``ignoredDifferenceRows`` where they differ, as UTF-16
  /// ranges of the text, sorted and apart; empty unless the places are to be shown.
  public var ignoredDifferencePlaces: [Range<Int>]

  /// How the line of each row ends in the file, shown among the invisible characters.
  public var lineEndings: [LineEnding]

  /// The rows tinted otherwise than their block, or tinted outside every block, by row: lines
  /// typed by hand, and the lines of a block that takes the texts of several sources, each in
  /// the tint of its own source.
  public var rowTints: [Int: BlockStyle]

  /// The parts of the text that show a preview of what a conflict offers rather than text of the
  /// file, in order and without overlap.
  ///
  /// A preview is drawn quieter than text and cannot be entered: the insertion point skips it,
  /// and copying leaves it out. Its rows are tinted in the color of its side.
  public var previews: [PanePreview]

  /// Whether a block without rows shows as a hairline across the pane, with its marks in the
  /// gutter, on the boundary where its lines are missing: on a pane that connects its changes to
  /// those of its neighbors rather than filling rows to line up with them.
  public var marksBlocksWithoutRows: Bool

  /// Creates the content of a pane.
  ///
  /// Without `lineEndings`, every row that shows a line ends with a line feed, except the last
  /// row, which has no ending.
  ///
  /// - Precondition: `lineNumbers` and `lineEndings` have one entry per row of `text`, and the
  ///   blocks are sorted, do not overlap and lie within the rows; the previews are sorted, do not
  ///   overlap and lie within the text; the rows of the tints lie within the rows.
  public init(
    text: String, lineNumbers: [Int32], blocks: [PaneBlock] = [],
    ignoredDifferenceRows: IndexSet = [], ignoredDifferencePlaces: [Range<Int>] = [],
    lineEndings: [LineEnding]? = nil, previews: [PanePreview] = [],
    rowTints: [Int: BlockStyle] = [:], marksBlocksWithoutRows: Bool = false
  ) {
    self.text = text
    self.marksBlocksWithoutRows = marksBlocksWithoutRows
    self.lineNumbers = lineNumbers
    self.blocks = blocks
    self.ignoredDifferenceRows = ignoredDifferenceRows
    self.ignoredDifferencePlaces = ignoredDifferencePlaces
    self.previews = previews
    self.rowTints = rowTints
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

  /// The index of the block without rows that lies on the boundary before `row`, if blocks
  /// without rows are marked and one lies there; `row` may be the number of rows, for the end.
  func markedBlockIndex(atBoundary row: Int) -> Int? {
    guard marksBlocksWithoutRows else { return nil }
    let index = blocks.partitioningIndex(where: { $0.rows.lowerBound >= row })
    guard index < blocks.count, blocks[index].rows == row..<row else { return nil }
    return index
  }

  /// The row that draws the hairline of a block without rows on the boundary before `row`: the
  /// row below the boundary, at its top, or at the end of the text the last row, at its bottom.
  func hairlineRow(ofBoundary row: Int) -> Int {
    min(row, lineNumbers.count - 1)
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

  /// Takes over an edit of the text, now `text`, that replaced `range` by `length` code units and
  /// rewrote rows as `change` says.
  ///
  /// The rewritten rows show lines of their own, numbered on from the line before them, and the
  /// lines after them follow on. Blocks keep their rows as ``RowChange`` maps them, previews their
  /// text. The owner of the content gives the pane the exact content afterwards; until then, this
  /// keeps every row described.
  mutating func takeOver(
    _ change: RowChange, replacing range: Range<Int>, length: Int, text: String
  ) {
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
    previews = previews.compactMap { $0.takingOver(range, length: length) }
    ignoredDifferenceRows = IndexSet(
      ignoredDifferenceRows.compactMap { Self.row($0, after: change) })
    let delta = length - range.count
    ignoredDifferencePlaces = ignoredDifferencePlaces.compactMap { place in
      if place.upperBound <= range.lowerBound { return place }
      if place.lowerBound >= range.upperBound {
        return place.lowerBound + delta..<place.upperBound + delta
      }
      return nil
    }
    rowTints = Dictionary(
      uniqueKeysWithValues: rowTints.compactMap { row, tint in
        Self.row(row, after: change).map { ($0, tint) }
      })
  }
}

extension PaneContent {
  /// Where `row` lies after an edit that rewrote rows as `change` says: a rewritten row drops
  /// out until the owner of the content says what it is, and the rows after them move.
  fileprivate static func row(_ row: Int, after change: RowChange) -> Int? {
    change.oldRows.contains(row) ? nil : change.newBoundary(of: row)
  }
}

/// A part of a pane's text that shows a preview of the lines one side offers for a conflict.
public struct PanePreview: Sendable, Hashable {
  /// The text of the preview, in UTF-16 code units, the line ending of its last line included.
  public var range: Range<Int>

  /// The side whose lines the preview shows, which tints its rows.
  public var role: ColorRole

  /// Creates a preview of the text in `range`, showing the lines of `role`.
  ///
  /// - Precondition: `range` is not empty.
  public init(range: Range<Int>, role: ColorRole) {
    precondition(!range.isEmpty, "A preview shows at least one character")
    self.range = range
    self.role = role
  }

  /// The preview after an edit that replaced `edited` by `length` code units, or `nil` if the
  /// edit took all of it.
  ///
  /// A preview after the edit moves with the text; one that the edit reached into keeps the part
  /// before the edit, or else the part after it.
  func takingOver(_ edited: Range<Int>, length: Int) -> PanePreview? {
    let delta = length - edited.count
    var preview = self
    if range.upperBound <= edited.lowerBound {
      return preview
    } else if range.lowerBound >= edited.upperBound {
      preview.range = range.lowerBound + delta..<range.upperBound + delta
    } else if range.lowerBound < edited.lowerBound {
      preview.range = range.lowerBound..<edited.lowerBound
    } else if range.upperBound > edited.upperBound {
      preview.range = edited.lowerBound + length..<range.upperBound + delta
    } else {
      return nil
    }
    return preview
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
