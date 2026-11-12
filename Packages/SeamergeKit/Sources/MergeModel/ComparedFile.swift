import Foundation
import TextIO

/// A file of a session split into lines as the comparison split it.
///
/// The split depends on the comparison mode, so it belongs to the session, not to the file.
struct ComparedFile: Sendable {
  /// The file.
  let file: SourceFile

  /// The text of the file as UTF-8 as the comparison saw it, starting at index 0.
  ///
  /// It differs from the file's text only where ``SourceFile/comparedText(in:)`` converts line
  /// endings, which keeps every offset.
  let utf8: Data

  /// The byte offset where each line starts, followed by the byte count.
  let lineStarts: [Int]

  /// The UTF-16 positions of the lines.
  let lineIndex: LineIndex

  /// Splits `text`, the compared text of `file`, at `lineStarts`.
  ///
  /// - Precondition: `lineStarts` meets the preconditions of `LineIndex`, which the engine's
  ///   split of valid UTF-8 always does: it splits only after CR or LF, and neither byte occurs
  ///   within a multi-byte scalar.
  init(file: SourceFile, text: Data, lineStarts: [Int]) {
    self.file = file
    utf8 = text
    self.lineStarts = lineStarts
    lineIndex = LineIndex(utf8: text, byteLineStarts: lineStarts)
  }

  /// The number of lines.
  var lineCount: Int { lineStarts.count - 1 }

  /// The bytes of `lines`, including the line ending of the last one.
  func byteRange(ofLines lines: Range<Int>) -> Range<Int> {
    lineStarts[lines.lowerBound]..<lineStarts[lines.upperBound]
  }

  /// The text of `lines` as the file has it, including the line ending of the last one.
  ///
  /// It differs from the compared text only in a file whose lines all end in CR, which the
  /// comparison sees with LF.
  func originalText(ofLines lines: Range<Int>) -> String {
    guard let bytes = file.utf8 else {
      preconditionFailure("A session never compares a binary file")
    }
    return String(decoding: bytes[byteRange(ofLines: lines)], as: UTF8.self)
  }

  /// The bytes of a line without its line ending.
  func contentByteRange(ofLine line: Int) -> Range<Int> {
    let start = lineStarts[line]
    let end = lineStarts[line + 1]
    return start..<(end - lineEndingLength(before: end, notBefore: start))
  }

  /// The number of UTF-16 code units of a line without its line ending.
  func contentUTF16Length(ofLine line: Int) -> Int {
    let end = lineStarts[line + 1]
    return lineIndex.utf16Range(ofLine: line).count
      - lineEndingLength(before: end, notBefore: lineStarts[line])
  }

  /// The line that contains the byte at `offset`.
  ///
  /// - Precondition: `offset` lies within `0..<utf8.count`.
  func line(containingByte offset: Int) -> Int {
    precondition((0..<utf8.count).contains(offset), "Byte \(offset) is outside the text")
    var low = 0
    var high = lineCount
    while high - low > 1 {
      let middle = (low + high) / 2
      if lineStarts[middle] <= offset { low = middle } else { high = middle }
    }
    return low
  }

  /// The length of the line ending CRLF, LF or CR that ends just before `end`, looking no
  /// further back than `start`.
  ///
  /// Line endings are ASCII, so their length is the same in bytes and in UTF-16.
  private func lineEndingLength(before end: Int, notBefore start: Int) -> Int {
    guard end > start else { return 0 }
    switch utf8[end - 1] {
    case UInt8(ascii: "\n"): return end - 1 > start && utf8[end - 2] == UInt8(ascii: "\r") ? 2 : 1
    case UInt8(ascii: "\r"): return 1
    default: return 0
    }
  }
}
