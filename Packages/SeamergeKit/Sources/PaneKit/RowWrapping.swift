import AppKit

/// How many screen lines each row of a pane takes at the width of its text.
///
/// Rows break as TextKit breaks them: at word boundaries, or between characters where a word is
/// longer than a line. Lines after the first of a row are indented beyond the row's own
/// indentation, and narrower by the indent.
///
/// The count is known before TextKit lays a row out, so that every row has its place and its
/// height from the start. Rows that fit for certain are not typeset: in a font of fixed width,
/// that is nearly every row of code.
struct RowWrapping {
  /// The width of the first screen line of a row.
  let width: CGFloat

  /// The attributes of the text, which decide the widths of its characters.
  private let attributes: [NSAttributedString.Key: Any]

  /// The most columns that fit on the first line.
  private let fittingColumns: Int

  /// The theme, which knows the indent of lines after the first.
  private let theme: Theme

  /// Breaks lines `width` wide of text with `attributes` in the font of `theme`.
  init(width: CGFloat, attributes: [NSAttributedString.Key: Any], theme: Theme) {
    self.width = width
    self.attributes = attributes
    self.theme = theme
    let characterWidth = theme.characterWidth
    fittingColumns = characterWidth > 0 ? Int((width / characterWidth).rounded(.down)) : 0
  }

  /// How far the lines after the first of `line`, a row's text, are indented.
  static func continuationIndent(of line: NSString, theme: Theme) -> CGFloat {
    var columns = 0
    for index in 0..<line.length {
      switch line.character(at: index) {
      case 0x20: columns += 1
      case 0x09: columns += theme.tabWidth - columns % theme.tabWidth
      default: return theme.continuationIndent(afterIndentationOf: columns)
      }
    }
    return theme.continuationIndent(afterIndentationOf: columns)
  }

  /// The rows among `rows` of `text`, whose rows `grid` knows, that take more than one line.
  func wrappedRows(_ rows: Range<Int>, of text: NSString, grid: RowGrid) -> [WrappedRows.Entry] {
    rows.compactMap { row in
      let lines = lines(ofRow: row, of: text, grid: grid)
      return lines > 1 ? WrappedRows.Entry(row: row, lines: lines) : nil
    }
  }

  /// The number of screen lines that `row` of `text` takes.
  func lines(ofRow row: Int, of text: NSString, grid: RowGrid) -> Int {
    if let columns = grid.exactColumns(ofRow: row), columns <= fittingColumns {
      return 1
    }
    let offsets = grid.offsets(ofRow: row)
    var length = offsets.count
    if length > 0 && text.character(at: offsets.upperBound - 1) == Self.lineFeed {
      length -= 1
    }
    return typesetLines(
      of: text.substring(with: NSRange(location: offsets.lowerBound, length: length)))
  }

  /// The number of lines that Core Text, which TextKit typesets with, breaks `line` into.
  private func typesetLines(of line: String) -> Int {
    let indent = Self.continuationIndent(of: line as NSString, theme: theme)
    let string = NSAttributedString(string: line, attributes: attributes)
    let typesetter = CTTypesetterCreateWithAttributedString(string)
    let length = string.length
    var start = 0
    var lines = 0
    while start < length {
      let lineWidth = lines == 0 ? width : max(width - indent, 1)
      start += max(CTTypesetterSuggestLineBreak(typesetter, start, Double(lineWidth)), 1)
      lines += 1
    }
    return max(lines, 1)
  }

  private static let lineFeed: unichar = 0x0A
}
