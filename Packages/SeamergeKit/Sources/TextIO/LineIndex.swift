import Foundation
import TextBasics

/// Converts between the byte positions of UTF-8 text and the UTF-16 positions that `NSString`
/// and TextKit use.
///
/// The index is built once per text in a single pass. It records where each line starts in
/// UTF-16; positions within a line are converted by scanning that line only.
package struct LineIndex: Sendable {
  private let utf8: Data
  private let byteLineStarts: LineStarts
  private let utf16LineStarts: LineStarts

  /// Creates the index of UTF-8 text split into lines.
  ///
  /// - Parameters:
  ///   - utf8: Valid UTF-8 text.
  ///   - byteLineStarts: The byte offset where each line starts, followed by `utf8.count`. Every
  ///     offset is at the start of a Unicode scalar and none is smaller than the one before.
  /// - Precondition: `byteLineStarts` starts with 0, ends with `utf8.count`, does not decrease,
  ///   and no offset falls inside a multi-byte scalar.
  package init(utf8: Data, byteLineStarts: LineStarts) {
    precondition(byteLineStarts[0] == 0, "Line starts must begin at offset 0")
    precondition(
      byteLineStarts[byteLineStarts.lineCount] == utf8.count,
      "Line starts must end with the byte count")
    var utf16LineStarts = [0]
    utf16LineStarts.reserveCapacity(byteLineStarts.lineCount + 1)
    utf8.withUnsafeBytes { bytes in
      var utf16Offset = 0
      for line in 0..<byteLineStarts.lineCount {
        let start = byteLineStarts[line]
        let end = byteLineStarts[line + 1]
        precondition(start <= end, "Line starts must not decrease")
        precondition(
          end == bytes.count || !UTF8.isContinuation(bytes[end]),
          "Line start \(end) falls inside a Unicode scalar")
        for byteOffset in start..<end {
          utf16Offset += Self.utf16Length(ofScalarStartingWith: bytes[byteOffset])
        }
        utf16LineStarts.append(utf16Offset)
      }
    }
    self.utf8 = utf8
    self.byteLineStarts = byteLineStarts
    self.utf16LineStarts = LineStarts(utf16LineStarts)
  }

  /// The number of lines.
  package var lineCount: Int { byteLineStarts.lineCount }

  /// The UTF-16 range of a line in the whole text, including its line ending.
  ///
  /// - Precondition: `line` lies within `0..<lineCount`.
  package func utf16Range(ofLine line: Int) -> Range<Int> {
    precondition((0..<lineCount).contains(line), "Line \(line) is out of range")
    return utf16LineStarts.range(ofLine: line)
  }

  /// The line that holds the UTF-16 offset `offset`; the end of the text belongs to the last
  /// line.
  package func line(containingUTF16Offset offset: Int) -> Int {
    utf16LineStarts.line(containing: offset)
  }

  /// The UTF-16 offset from the start of a line that corresponds to a byte offset from the start
  /// of the same line.
  ///
  /// - Precondition: `line` lies within `0..<lineCount`, and `byteOffset` lies within the line or
  ///   at its end and at the start of a Unicode scalar.
  package func utf16Offset(ofByteOffset byteOffset: Int, inLine line: Int) -> Int {
    let lineBytes = byteRange(ofLine: line)
    precondition(
      (0...lineBytes.count).contains(byteOffset), "Byte offset \(byteOffset) is outside the line")
    return utf8.withUnsafeBytes { bytes in
      let end = lineBytes.lowerBound + byteOffset
      precondition(
        end == bytes.count || !UTF8.isContinuation(bytes[end]),
        "Byte offset \(byteOffset) falls inside a Unicode scalar")
      var utf16Offset = 0
      for index in lineBytes.lowerBound..<end {
        utf16Offset += Self.utf16Length(ofScalarStartingWith: bytes[index])
      }
      return utf16Offset
    }
  }

  /// The byte offset from the start of a line that corresponds to a UTF-16 offset from the start
  /// of the same line.
  ///
  /// - Precondition: `line` lies within `0..<lineCount`, and `utf16Offset` lies within the line
  ///   or at its end and not between the two halves of a surrogate pair.
  package func byteOffset(ofUTF16Offset utf16Offset: Int, inLine line: Int) -> Int {
    let lineBytes = byteRange(ofLine: line)
    precondition(
      (0...utf16Range(ofLine: line).count).contains(utf16Offset),
      "UTF-16 offset \(utf16Offset) is outside the line")
    return utf8.withUnsafeBytes { bytes in
      var index = lineBytes.lowerBound
      var reached = 0
      while reached < utf16Offset {
        reached += Self.utf16Length(ofScalarStartingWith: bytes[index])
        index += 1
        while index < lineBytes.upperBound, UTF8.isContinuation(bytes[index]) { index += 1 }
      }
      precondition(
        reached == utf16Offset, "UTF-16 offset \(utf16Offset) falls inside a surrogate pair")
      return index - lineBytes.lowerBound
    }
  }

  private func byteRange(ofLine line: Int) -> Range<Int> {
    precondition((0..<lineCount).contains(line), "Line \(line) is out of range")
    return byteLineStarts.range(ofLine: line)
  }

  /// The number of UTF-16 code units of the scalar that a byte begins, or 0 for a byte that
  /// continues a scalar.
  ///
  /// Only scalars beyond the Basic Multilingual Plane, which take four bytes, need two.
  private static func utf16Length(ofScalarStartingWith byte: UInt8) -> Int {
    if UTF8.isContinuation(byte) { 0 } else if byte >= 0xF0 { 2 } else { 1 }
  }
}
