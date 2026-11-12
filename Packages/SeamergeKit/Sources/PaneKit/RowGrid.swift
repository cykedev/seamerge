/// The rows of a pane's text: where each starts and how many columns the widest one takes.
///
/// Offsets are UTF-16 offsets, as TextKit counts them. Row *r* is paragraph *r*; rows are
/// separated by line feeds, so a text that ends with one has an empty last row.
struct RowGrid {
  /// The offset at which each row starts.
  private let rowStarts: [Int]

  /// The length of the text.
  let textLength: Int

  /// The number of columns that the widest row takes, with tabs expanded.
  let widestRowColumns: Int

  /// Finds the rows of `text`, expanding tabs to multiples of `tabWidth` columns.
  init(text: String, tabWidth: Int) {
    var rowStarts = [0]
    var offset = 0
    var columns = 0
    var widestRowColumns = 0
    for scalar in text.unicodeScalars {
      offset += scalar.utf16.count
      switch scalar {
      case "\n":
        rowStarts.append(offset)
        widestRowColumns = max(widestRowColumns, columns)
        columns = 0
      case "\t":
        columns += tabWidth - columns % tabWidth
      default:
        columns += Self.columns(of: scalar)
      }
    }
    self.rowStarts = rowStarts
    self.textLength = offset
    self.widestRowColumns = max(widestRowColumns, columns)
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
