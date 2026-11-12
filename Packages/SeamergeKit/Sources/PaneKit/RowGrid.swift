import Foundation

/// The rows of a pane's text: where each starts and how many columns the widest one takes.
///
/// Offsets are UTF-16 offsets, as TextKit counts them. Row *r* is paragraph *r*; rows are
/// separated by line feeds, so a text that ends with one has an empty last row.
struct RowGrid {
  /// The offset at which each row starts.
  private var rowStarts: [Int]

  /// The length of the text.
  private(set) var textLength: Int

  /// The number of columns that the widest row takes, with tabs expanded.
  ///
  /// After an edit, the widest row that the edit left or made counts as well, even if the edit
  /// removed it, so that the width does not shrink under the user's hands while they type.
  private(set) var widestRowColumns: Int

  /// The width of a tab, in columns.
  private let tabWidth: Int

  /// Finds the rows of `text`, expanding tabs to multiples of `tabWidth` columns.
  init(text: String, tabWidth: Int) {
    var rowStarts = [0]
    var offset = 0
    let widestRowColumns = Self.measure(text.unicodeScalars, tabWidth: tabWidth) { length in
      offset += length
      rowStarts.append(offset)
    }
    self.rowStarts = rowStarts
    self.textLength = text.utf16.count
    self.widestRowColumns = widestRowColumns
    self.tabWidth = tabWidth
  }

  /// Takes over an edit of the text that replaced `range` by `length` code units, given the text
  /// after the edit, and returns the rows that the edit rewrote: those it touched before, and
  /// those they became.
  mutating func replace(_ range: Range<Int>, withLength length: Int, in text: NSString)
    -> RowChange
  {
    let firstRow = row(containingOffset: range.lowerBound)
    let lastRow = row(containingOffset: range.upperBound)
    let rowStart = rowStarts[firstRow]
    let delta = length - range.count
    // The rewritten rows reach from the start of the first to the end of the last, which now lies
    // `delta` further on.
    let oldEnd = lastRow + 1 < rowStarts.count ? rowStarts[lastRow + 1] - 1 : textLength
    let newEnd = oldEnd + delta
    var newStarts: [Int] = []
    let rows = text.substring(with: NSRange(location: rowStart, length: newEnd - rowStart))
    var offset = rowStart
    let columns = Self.measure(rows.unicodeScalars, tabWidth: tabWidth) { rowLength in
      offset += rowLength
      newStarts.append(offset)
    }
    rowStarts.replaceSubrange(firstRow + 1..<lastRow + 1, with: newStarts)
    for row in firstRow + 1 + newStarts.count..<rowStarts.count {
      rowStarts[row] += delta
    }
    textLength += delta
    widestRowColumns = max(widestRowColumns, columns)
    return RowChange(
      oldRows: firstRow..<lastRow + 1, newRows: firstRow..<firstRow + newStarts.count + 1)
  }

  /// Measures the rows of `scalars` and returns the columns of the widest; `rowEnded` learns the
  /// length of each row that a line feed ends, the line feed included.
  private static func measure(
    _ scalars: some Sequence<Unicode.Scalar>, tabWidth: Int, rowEnded: (Int) -> Void
  ) -> Int {
    var length = 0
    var columns = 0
    var widestRowColumns = 0
    for scalar in scalars {
      length += scalar.utf16.count
      switch scalar {
      case "\n":
        rowEnded(length)
        length = 0
        widestRowColumns = max(widestRowColumns, columns)
        columns = 0
      case "\t":
        columns += tabWidth - columns % tabWidth
      default:
        columns += Self.columns(of: scalar)
      }
    }
    return max(widestRowColumns, columns)
  }

  /// The number of rows.
  var rowCount: Int { rowStarts.count }

  /// Whether the text ends with a line feed, so that its last row is empty.
  var endsWithEmptyRow: Bool { rowStarts.count > 1 && rowStarts[rowStarts.count - 1] == textLength }

  /// The row that the character at `offset` belongs to; the end of the text belongs to the last
  /// row.
  func row(containingOffset offset: Int) -> Int {
    var low = 0
    var high = rowStarts.count
    while high - low > 1 {
      let middle = (low + high) / 2
      if rowStarts[middle] <= offset {
        low = middle
      } else {
        high = middle
      }
    }
    return low
  }

  /// The offsets of `row`, its line feed included.
  func offsets(ofRow row: Int) -> Range<Int> {
    rowStarts[row]..<(row + 1 < rowStarts.count ? rowStarts[row + 1] : textLength)
  }

  /// The rows that TextKit lays out in the paragraph from `start` to `end`.
  ///
  /// That is one row, except for the paragraph before an empty last row: TextKit gives the empty
  /// last row no layout fragment of its own but lays it out as part of that paragraph.
  func rows(ofParagraphFrom start: Int, to end: Int) -> Range<Int> {
    let row = row(containingOffset: start)
    let isLastParagraph = end >= textLength
    return row..<(isLastParagraph ? rowCount : row + 1)
  }

  /// The offsets of the paragraphs that lay out `rows`, line feeds included.
  func paragraphOffsets(ofRows rows: Range<Int>) -> Range<Int> {
    var first = rows.lowerBound
    if endsWithEmptyRow && first == rowCount - 1 {
      first = max(first - 1, 0)
    }
    let end = rows.upperBound < rowCount ? rowStarts[rows.upperBound] : textLength
    return rowStarts[first]..<max(end, rowStarts[first])
  }

  /// The number of columns a character takes in a font of fixed width.
  ///
  /// Wide East Asian characters and emoji take two, combining marks none. The count serves only
  /// to size the text view before TextKit lays the text out, so an approximation is enough.
  private static func columns(of scalar: Unicode.Scalar) -> Int {
    let value = scalar.value
    if value < 0x300 { return 1 }
    switch value {
    case 0x1100...0x115F, 0x2E80...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE4F,
      0xFF00...0xFF60, 0xFFE0...0xFFE6, 0x1F300...0x1FAFF, 0x20000...0x3FFFD:
      return 2
    default:
      switch scalar.properties.generalCategory {
      case .nonspacingMark, .enclosingMark, .format: return 0
      default: return scalar.properties.isEmojiPresentation ? 2 : 1
      }
    }
  }
}

/// The rows that an edit rewrote: the rows it touched, and the rows they became.
///
/// Rows before them keep their place; rows after them move by the difference in count.
struct RowChange: Equatable {
  /// The rows of the text before the edit that the edit touched.
  var oldRows: Range<Int>

  /// The rows of the text after the edit that took their place.
  var newRows: Range<Int>

  /// The number of rows that the edit added, negative if it removed rows.
  var rowDelta: Int { newRows.count - oldRows.count }

  /// Where boundary `row` of the rows before the edit lies after it: unchanged before the edit,
  /// moved after it, and within the rewritten rows, after all of them, so that the rewritten rows
  /// go to the range in which the edit starts, as typed text does.
  ///
  /// The mapping keeps the order of boundaries, so ranges of rows stay sorted and apart.
  func newBoundary(of row: Int) -> Int {
    if row <= oldRows.lowerBound { return row }
    if row >= oldRows.upperBound { return row + rowDelta }
    return newRows.upperBound
  }

  /// Where `rows` of the text before the edit lie after it.
  func newRows(of rows: Range<Int>) -> Range<Int> {
    newBoundary(of: rows.lowerBound)..<newBoundary(of: rows.upperBound)
  }
}
