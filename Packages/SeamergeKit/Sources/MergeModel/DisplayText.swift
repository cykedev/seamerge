import Foundation

/// The text a pane shows for one input: the lines of its file laid out on the row grid.
///
/// Each row of the grid is one line of ``string``, and rows are separated by LF, so the string
/// has exactly as many lines as the grid has rows. A row shows the text of its line without the
/// line ending; a filler row is empty. Characters that would break a row into two lines in a text
/// view (a carriage return within a line, NEL, the line separator and the paragraph separator)
/// are shown as a control picture of the same UTF-16 length, so that a position within a line is
/// the same in the file and in the row.
public struct DisplayText: Sendable {
  /// The text of all rows, separated by LF.
  public let string: String

  /// The UTF-16 offset where each row starts, followed by the length of ``string`` plus one, as
  /// if the last row ended with a separator too.
  private let rowStarts: [Int]

  /// Lays out the lines of `file` on the rows of `blocks`.
  init(file: ComparedFile, role: Role, blocks: [Block]) {
    let rowCount = blocks.reduce(0) { $0 + $1.rowCount }
    var bytes: [UInt8] = []
    bytes.reserveCapacity(file.utf8.count + rowCount)
    var rowStarts: [Int] = []
    rowStarts.reserveCapacity(rowCount + 1)
    var utf16Offset = 0
    file.utf8.withUnsafeBytes { text in
      for block in blocks {
        let lines = block.lines(in: role)
        for row in 0..<block.rowCount {
          if !rowStarts.isEmpty { bytes.append(UInt8(ascii: "\n")) }
          rowStarts.append(utf16Offset)
          if row < lines.count {
            let line = lines.lowerBound + row
            Self.appendShowingLineBreaks(
              text[file.contentByteRange(ofLine: line)], to: &bytes)
            utf16Offset += file.contentUTF16Length(ofLine: line)
          }
          utf16Offset += 1
        }
      }
    }
    rowStarts.append(utf16Offset)
    string = String(decoding: bytes, as: UTF8.self)
    self.rowStarts = rowStarts
  }

  /// The number of rows.
  public var rowCount: Int { rowStarts.count - 1 }

  /// The UTF-16 range of a row in ``string``, without the separator that follows it.
  ///
  /// - Precondition: `row` lies within `0..<rowCount`.
  public func utf16Range(ofRow row: Int) -> Range<Int> {
    precondition((0..<rowCount).contains(row), "Row \(row) is out of range")
    return rowStarts[row]..<(rowStarts[row + 1] - 1)
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
