import Foundation
import MergeEngine

/// One line for display: control characters and bytes that are not valid
/// UTF-8 are shown as `\xNN`, a CRLF ending as `␍␊`, a CR ending as `␍`.
/// Returns whether the line had a line ending at all.
func displayed(_ line: Data) -> (text: String, hasLineEnding: Bool) {
  var content = line
  var ending = ""
  var hasLineEnding = true
  if content.last == UInt8(ascii: "\n") {
    content.removeLast()
    if content.last == UInt8(ascii: "\r") {
      content.removeLast()
      ending = "␍␊"
    }
  } else if content.last == UInt8(ascii: "\r") {
    content.removeLast()
    ending = "␍"
  } else {
    hasLineEnding = false
  }
  return (escaped(content) + ending, hasLineEnding)
}

func escaped(_ bytes: Data) -> String {
  func hex(_ byte: UInt8) -> String {
    "\\x" + String(byte, radix: 16, uppercase: true).leftPadded(2)
  }

  if let text = String(data: bytes, encoding: .utf8) {
    return text.unicodeScalars.map { scalar in
      scalar.value < 0x20 && scalar != "\t" || scalar.value == 0x7F
        ? hex(UInt8(scalar.value)) : String(scalar)
    }.joined()
  }
  return bytes.map { byte in
    (0x20..<0x7F).contains(byte) || byte == UInt8(ascii: "\t")
      ? String(UnicodeScalar(byte)) : hex(byte)
  }.joined()
}

/// A span as 1-based line numbers, or the position after which it lies if it
/// is empty.
func lineNumbers(_ span: Span) -> String {
  switch span.lines.count {
  case 0: "after \(span.lines.lowerBound)"
  case 1: "\(span.lines.lowerBound + 1)"
  default: "\(span.lines.lowerBound + 1)-\(span.lines.upperBound)"
  }
}

/// The lines of `span`, each prefixed with `prefix`.
func listing(_ span: Span, in buffer: LineBuffer, prefix: String) -> [String] {
  span.lines.flatMap { index in
    let line = displayed(buffer.line(index))
    return line.hasLineEnding
      ? ["\(prefix)\(line.text)"] : ["\(prefix)\(line.text)", "\\ No newline at end of file"]
  }
}

extension String {
  func leftPadded(_ width: Int, with character: Character = "0") -> String {
    count >= width ? self : String(repeating: character, count: width - count) + self
  }

  func rightPadded(_ width: Int) -> String {
    count >= width ? self : self + String(repeating: " ", count: width - count)
  }
}
