import Foundation
import TextBasics

/// The text a pane shows: the lines of one input laid out on the row grid, the lines of its file
/// alone, or the lines of both files of a comparison in a single column.
///
/// Each row is one line of ``string``, and rows are separated by LF, so the string has exactly
/// as many lines as there are rows. A row shows the text of its line without the line ending; a
/// filler row of the grid is empty. Characters that would break a row into two lines in a text
/// view (a carriage return within a line, NEL, the line separator and the paragraph separator)
/// are shown as a control picture of the same UTF-16 length, so that a position within a line is
/// the same in the file and in the row.
public struct DisplayText: Sendable {
  /// The text of all rows, separated by LF.
  public let string: String

  /// The UTF-16 offset where each row starts, followed by the length of ``string`` plus one, as
  /// if the last row ended with a separator too.
  private let rowStarts: LineStarts

  /// Lays out the lines of `file` on the rows of `blocks`.
  init(file: ComparedFile, role: Role, blocks: [Block]) {
    let rows = blocks.lazy.flatMap { block in
      let lines = block.lines(in: role)
      return (0..<block.rowCount).lazy.map {
        $0 < lines.count ? RowSource(file: 0, line: lines.lowerBound + $0) : nil
      }
    }
    self.init(files: [file], rows: rows, rowCount: blocks.reduce(0) { $0 + $1.rowCount })
  }

  /// Lays out each line of `file` on a row of its own, without filler rows.
  init(linesOf file: ComparedFile) {
    self.init(
      files: [file], rows: (0..<file.lineCount).lazy.map { RowSource(file: 0, line: $0) },
      rowCount: file.lineCount)
  }

  /// The line that a row shows: the index of its file among those laid out, and the line.
  struct RowSource {
    var file: Int
    var line: Int
  }

  /// Lays out the `rowCount` rows that `rows` gives, each the line of `files` it names or a
  /// filler row for `nil`.
  init(files: [ComparedFile], rows: some Sequence<RowSource?>, rowCount: Int) {
    var bytes: [UInt8] = []
    bytes.reserveCapacity(files.reduce(rowCount) { $0 + $1.utf8.count })
    var rowStarts: [Int] = []
    rowStarts.reserveCapacity(rowCount + 1)
    var utf16Offset = 0
    for source in rows {
      if !rowStarts.isEmpty { bytes.append(UInt8(ascii: "\n")) }
      rowStarts.append(utf16Offset)
      if let source {
        let file = files[source.file]
        file.utf8.withUnsafeBytes { text in
          Self.appendShowingLineBreaks(text[file.contentByteRange(ofLine: source.line)], to: &bytes)
        }
        utf16Offset += file.contentUTF16Length(ofLine: source.line)
      }
      utf16Offset += 1
    }
    rowStarts.append(utf16Offset)
    string = String(decoding: bytes, as: UTF8.self)
    self.rowStarts = LineStarts(rowStarts)
  }

  /// The number of rows.
  public var rowCount: Int { rowStarts.lineCount }

  /// The UTF-16 range of a row in ``string``, without the separator that follows it.
  ///
  /// - Precondition: `row` lies within `0..<rowCount`.
  public func utf16Range(ofRow row: Int) -> Range<Int> {
    precondition((0..<rowCount).contains(row), "Row \(row) is out of range")
    return rowStarts[row]..<(rowStarts[row + 1] - 1)
  }

  /// The row that holds the UTF-16 offset `offset`, the end of the row and its separator
  /// counting as part of the row.
  ///
  /// - Precondition: `offset` lies within `0..<string.utf16.count + 1`, and there is a row.
  func row(containingOffset offset: Int) -> Int {
    precondition(
      rowCount > 0 && (0..<rowStarts[rowCount]).contains(offset), "Offset \(offset) is out of range"
    )
    return rowStarts.line(containing: offset)
  }

  /// Appends UTF-8 bytes and replaces each character that ends a line in a text view with a
  /// control picture: CR with U+240D, NEL, U+2028 and U+2029 with U+2424.
  ///
  /// Each replaced character and its picture are one UTF-16 code unit long.
  private static func appendShowingLineBreaks(
    _ text: Slice<UnsafeRawBufferPointer>, to bytes: inout [UInt8]
  ) {
    let carriageReturnPicture: [UInt8] = [0xE2, 0x90, 0x8D]
    let newlinePicture: [UInt8] = [0xE2, 0x90, 0xA4]
    var index = text.startIndex
    var copied = index
    while index < text.endIndex {
      let replacedLength: Int
      let picture: [UInt8]
      switch text[index] {
      case 0x0D:
        (replacedLength, picture) = (1, carriageReturnPicture)
      case 0xC2 where index + 1 < text.endIndex && text[index + 1] == 0x85:
        (replacedLength, picture) = (2, newlinePicture)
      case 0xE2
      where index + 2 < text.endIndex && text[index + 1] == 0x80
        && (text[index + 2] == 0xA8 || text[index + 2] == 0xA9):
        (replacedLength, picture) = (3, newlinePicture)
      default:
        index += 1
        continue
      }
      bytes.append(contentsOf: text[copied..<index])
      bytes.append(contentsOf: picture)
      index += replacedLength
      copied = index
    }
    bytes.append(contentsOf: text[copied..<text.endIndex])
  }
}
