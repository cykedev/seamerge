import Foundation
import TextBasics

/// A UTF-8 text and the byte offsets where its lines start.
struct LineText: Sendable {
  /// The text, starting at index 0.
  let utf8: Data

  /// The byte offset where each line starts, followed by the byte count.
  let lineStarts: LineStarts

  /// A text split at `lineStarts`.
  init(utf8: Data, lineStarts: LineStarts) {
    self.utf8 = utf8
    self.lineStarts = lineStarts
  }

  /// Splits `utf8` into lines as the engine does in `mode`.
  ///
  /// A line ends after each LF, and in every mode other than ``ComparisonMode/exact`` also after
  /// each CR that no LF follows. An empty text has no line.
  init(splitting utf8: Data, in mode: ComparisonMode) {
    var lineStarts = [0]
    utf8.withUnsafeBytes { bytes in
      for (index, byte) in bytes.enumerated() {
        let endsLine =
          switch byte {
          case UInt8(ascii: "\n"): true
          case UInt8(ascii: "\r"):
            mode != .exact && (index + 1 == bytes.count || bytes[index + 1] != UInt8(ascii: "\n"))
          default: false
          }
        if endsLine, index + 1 < bytes.count { lineStarts.append(index + 1) }
      }
    }
    if !utf8.isEmpty { lineStarts.append(utf8.count) }
    self.init(utf8: utf8, lineStarts: LineStarts(lineStarts))
  }

  /// The number of lines.
  var lineCount: Int { lineStarts.lineCount }

  /// The bytes of `lines`, including the line ending of the last one.
  func byteRange(ofLines lines: Range<Int>) -> Range<Int> {
    lineStarts[lines.lowerBound]..<lineStarts[lines.upperBound]
  }

  /// The text of `lines`, including the line ending of the last one.
  func bytes(ofLines lines: Range<Int>) -> Data {
    utf8.subdata(in: byteRange(ofLines: lines))
  }

  /// The bytes of a line without its line ending.
  func contentByteRange(ofLine line: Int) -> Range<Int> {
    let start = lineStarts[line]
    let end = lineStarts[line + 1]
    return start..<(end - lineEndingLength(before: end, notBefore: start))
  }

  /// The length of the line ending CRLF, LF or CR that ends just before `end`, looking no
  /// further back than `start`.
  ///
  /// Line endings are ASCII, so their length is the same in bytes and in UTF-16.
  func lineEndingLength(before end: Int, notBefore start: Int) -> Int {
    guard end > start else { return 0 }
    switch utf8[end - 1] {
    case UInt8(ascii: "\n"): return end - 1 > start && utf8[end - 2] == UInt8(ascii: "\r") ? 2 : 1
    case UInt8(ascii: "\r"): return 1
    default: return 0
    }
  }
}
