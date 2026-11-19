package import Foundation
package import TextBasics

/// What a pane shows: its rows on the grid, the line number of each row and the blocks.
///
/// Row *r* is paragraph *r* of the text, so panes with the same number of rows have the same
/// height and their rows line up.
package struct PaneContent: Sendable {
  /// The text of the rows, separated by line feeds.
  package var text: String

  /// The zero-based number of the line that each row shows, or -1 for a filler row.
  ///
  /// In a pane with ``sideLineNumbers``, the numbers count the rows of the pane itself, from 0,
  /// and the gutter shows the numbers of both sides instead.
  package var lineNumbers: [Int32]

  /// The line numbers of both files of a comparison, for a pane that shows them in one column,
  /// which the gutter shows in two columns; `nil` for a pane of one file.
  ///
  /// An edit of the text drops them, as it cannot tell which file the rewritten rows belong to;
  /// the gutter then numbers the rows of the pane until the owner gives the exact content.
  package private(set) var sideLineNumbers: SideLineNumbers?

  /// The blocks, in row order and without overlap.
  ///
  /// Rows outside every block are unchanged.
  package var blocks: [PaneBlock]

  /// The rows whose line differs from the line it is compared with, although the comparison
  /// counts both as equal.
  package var ignoredDifferenceRows: IndexSet

  /// The places within the rows of ``ignoredDifferenceRows`` where they differ, as UTF-16
  /// ranges of the text, sorted and apart; empty unless the places are to be shown.
  package var ignoredDifferencePlaces: [Range<Int>]

  /// How the line of each row ends in the file, shown among the invisible characters; `nil` for
  /// the last line of a file without a final line break and for a filler row.
  ///
  /// The text of a pane separates its rows with line feeds whatever the file uses, so the pane
  /// learns the real ending of each line from here.
  package var lineEndings: [LineEnding?]

  /// The rows tinted otherwise than their block, or tinted outside every block, by row: lines
  /// typed by hand, and the lines of a block that takes the texts of several sources, each in
  /// the tint of its own source.
  package var rowTints: [Int: BlockStyle]

  /// The parts of the text that show a preview of what a conflict offers rather than text of the
  /// file, in order and without overlap.
  ///
  /// A preview is drawn quieter than text and cannot be entered: the insertion point skips it,
  /// and copying leaves it out. Its rows are tinted in the color of its side.
  package var previews: [PanePreview]

  /// Whether a block without rows shows as a hairline across the pane, with its marks in the
  /// gutter, on the boundary where its lines are missing: on a pane that connects its changes to
  /// those of its neighbors rather than filling rows to line up with them.
  package var marksBlocksWithoutRows: Bool

  /// Creates the content of a pane.
  ///
  /// Without `lineEndings`, every row that shows a line ends with a line feed, except the last
  /// row, which has no ending.
  ///
  /// - Precondition: `lineNumbers` and `lineEndings` have one entry per row of `text`, and the
  ///   blocks are sorted, do not overlap and lie within the rows; the previews are sorted, do not
  ///   overlap and lie within the text; the rows of the tints lie within the rows;
  ///   `sideLineNumbers` has as many rows as `lineNumbers`.
  package init(
    text: String, lineNumbers: [Int32], sideLineNumbers: SideLineNumbers? = nil,
    blocks: [PaneBlock] = [], ignoredDifferenceRows: IndexSet = [],
    ignoredDifferencePlaces: [Range<Int>] = [], lineEndings: [LineEnding?]? = nil,
    previews: [PanePreview] = [], rowTints: [Int: BlockStyle] = [:],
    marksBlocksWithoutRows: Bool = false
  ) {
    precondition(
      sideLineNumbers.map { $0.rowCount == lineNumbers.count } ?? true,
      "Line numbers of both sides for another number of rows")
    self.text = text
    self.sideLineNumbers = sideLineNumbers
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
        lineNumbers[row] < 0 || row == lineNumbers.count - 1 ? nil : .lf
      }
  }

  /// A pane without text.
  package static let empty = PaneContent(text: "", lineNumbers: [-1])

  /// The index of the block that `row` belongs to, or `nil` if the row is unchanged.
  func blockIndex(atRow row: Int) -> Int? {
    let index = blocks.partitioningIndex { $0.rows.upperBound > row }
    guard index < blocks.count, blocks[index].rows.contains(row) else { return nil }
    return index
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
      if let ending = lineEndings[row] { return ending }
    }
    var counts: [LineEnding: Int] = [:]
    for case let ending? in lineEndings {
      counts[ending, default: 0] += 1
    }
    return counts.max { $0.value < $1.value }?.key ?? .lf
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
    sideLineNumbers = nil
    for index in blocks.indices {
      blocks[index].takeOver(change)
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
package struct PanePreview: Sendable, Hashable {
  /// The text of the preview, in UTF-16 code units, the line ending of its last line included.
  package var range: Range<Int>

  /// The side whose lines the preview shows, which tints its rows.
  package var role: ColorRole

  /// Creates a preview of the text in `range`, showing the lines of `role`.
  ///
  /// - Precondition: `range` is not empty.
  package init(range: Range<Int>, role: ColorRole) {
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
package struct PaneBlock: Sendable, Hashable {
  /// The rows of the block on the grid.
  package var rows: Range<Int>

  /// How the rows are tinted.
  package var style: BlockStyle

  /// How this pane's side changed the block, or `nil` if it did not.
  package var marker: Marker?

  /// The mark of a conflict, shown on the base pane, or on B while the base is hidden.
  package var conflict: ConflictMarker?

  /// The arrow to the other end, if the block is an end of a move; it takes the place of
  /// ``marker``, which still says how the side changed the block.
  package var move: MoveMark?

  /// The rows of the second file below those of the first, in a pane that shows both files of
  /// a comparison in one column, with a tint and a mark of their own; `nil` where the block has
  /// one tint.
  ///
  /// ``style`` and ``marker`` then belong to the rows above the part. A hairline divides the two
  /// parts as it divides two blocks that touch.
  package var lowerPart: PaneBlockPart?

  /// Creates a block.
  ///
  /// - Precondition: `lowerPart` starts below the first row of the block and within it.
  package init(
    rows: Range<Int>, style: BlockStyle, marker: Marker? = nil, conflict: ConflictMarker? = nil,
    move: MoveMark? = nil, lowerPart: PaneBlockPart? = nil
  ) {
    precondition(
      lowerPart.map { rows.dropFirst().contains($0.firstRow) } ?? true,
      "The lower part of a block starts below its first row and within it")
    self.rows = rows
    self.style = style
    self.marker = marker
    self.conflict = conflict
    self.move = move
    self.lowerPart = lowerPart
  }

  /// The lower part if `row` lies in it.
  func lowerPart(containingRow row: Int) -> PaneBlockPart? {
    lowerPart.flatMap { row >= $0.firstRow ? $0 : nil }
  }

  /// How `row` of the block is tinted: in the style of the lower part if it lies there.
  func style(atRow row: Int) -> BlockStyle {
    lowerPart(containingRow: row)?.style ?? style
  }

  /// Takes over an edit that rewrote rows as `change` says: the rows move or grow with it, and
  /// the lower part stays while it still starts within them below their first row.
  fileprivate mutating func takeOver(_ change: RowChange) {
    rows = change.newRows(of: rows)
    guard var part = lowerPart else { return }
    part.firstRow = change.newBoundary(of: part.firstRow)
    lowerPart = rows.dropFirst().contains(part.firstRow) ? part : nil
  }
}

/// The lower part of a block in a pane that shows both files of a comparison in one column: the
/// rows of the second file, from a row of the block to its end.
package struct PaneBlockPart: Sendable, Hashable {
  /// The first row of the part, which runs to the end of its block.
  package var firstRow: Int

  /// How the rows of the part are tinted.
  package var style: BlockStyle

  /// How the second file changed the block, shown at the first row of the part, or `nil`.
  package var marker: Marker?

  /// Creates the part of a block from `firstRow` to the end of the block.
  package init(firstRow: Int, style: BlockStyle, marker: Marker? = nil) {
    self.firstRow = firstRow
    self.style = style
    self.marker = marker
  }
}
