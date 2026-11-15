import Foundation
import TextIO

/// A file of a session split into lines as the comparison split it.
///
/// The split depends on the comparison mode, so it belongs to the session, not to the file.
struct ComparedFile: Sendable {
  /// The file.
  let file: SourceFile

  /// The text of the file as UTF-8 and its lines, as shown.
  ///
  /// It differs from the file's text only where ``SourceFile/comparedText(in:)`` converts line
  /// endings, which keeps every offset.
  let text: LineText

  /// The text the engine compared: ``text`` without what the ignore rules match, line for line,
  /// or ``text`` itself in a comparison without rules.
  let compared: LineText

  /// The text that the ignore rules match.
  let ruleMatches: RuleMatches

  /// The UTF-16 positions of the lines.
  let lineIndex: LineIndex

  /// Splits `text`, the compared text of `file`, at `lineStarts`, for a comparison without
  /// ignore rules.
  ///
  /// - Precondition: `lineStarts` meets the preconditions of `LineIndex`, which the engine's
  ///   split of valid UTF-8 always does: it splits only after CR or LF, and neither byte occurs
  ///   within a multi-byte scalar.
  init(file: SourceFile, text: Data, lineStarts: [Int]) {
    self.file = file
    self.text = LineText(utf8: text, lineStarts: lineStarts)
    compared = self.text
    ruleMatches = .none
    lineIndex = LineIndex(utf8: text, byteLineStarts: lineStarts)
  }

  /// The file `file` as the engine compared it, masked by `mask`.
  init(file: SourceFile, mask: IgnoreMask) {
    self.file = file
    text = mask.text
    compared = mask.masked
    ruleMatches = mask.matches
    lineIndex = mask.lineIndex
  }

  /// The text of the file as UTF-8, starting at index 0.
  var utf8: Data { text.utf8 }

  /// The byte offset where each line starts, followed by the byte count.
  var lineStarts: [Int] { text.lineStarts }

  /// The number of lines.
  var lineCount: Int { lineStarts.count - 1 }

  /// The bytes of `lines`, including the line ending of the last one.
  func byteRange(ofLines lines: Range<Int>) -> Range<Int> {
    text.byteRange(ofLines: lines)
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
    text.contentByteRange(ofLine: line)
  }

  /// The number of UTF-16 code units of a line without its line ending.
  func contentUTF16Length(ofLine line: Int) -> Int {
    let end = lineStarts[line + 1]
    return lineIndex.utf16Range(ofLine: line).count
      - text.lineEndingLength(before: end, notBefore: lineStarts[line])
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

  /// Whether a line starts at byte `offset`, counting the end of the text as the start of the
  /// line after the last one.
  ///
  /// - Precondition: `offset` lies within `0...utf8.count`.
  func startsLine(at offset: Int) -> Bool {
    offset == utf8.count || lineStarts[line(containingByte: offset)] == offset
  }

  /// Whether the content of a line ends at byte `offset`: a line ending follows, or the text
  /// ends there without one.
  ///
  /// - Precondition: `offset` lies within `0...utf8.count`.
  func endsLineContent(at offset: Int) -> Bool {
    guard offset < utf8.count else {
      return utf8.last.map { !Self.isLineEnding($0) } ?? true
    }
    return Self.isLineEnding(utf8[offset])
  }

  private static func isLineEnding(_ byte: UInt8) -> Bool {
    byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r")
  }
}
