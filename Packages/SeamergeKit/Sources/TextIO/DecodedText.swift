import Foundation
import TextBasics

/// The text of a file, decoded, together with what is needed to write it back in the same form.
package struct DecodedText: Sendable {
  /// The encoding the file is in.
  package let encoding: TextEncoding

  /// Whether the file starts with the byte order mark of ``encoding``.
  package let hasByteOrderMark: Bool

  /// The text as UTF-8, without a byte order mark and with line endings as they are in the file.
  package let utf8: Data

  /// The text, with line endings as they are in the file.
  package let text: String

  /// The line endings of the text, or `nil` if it has no line break.
  package let lineEndingStyle: LineEndingStyle?

  /// Whether the text has characters after its last line break, so that its last line has no
  /// line ending.
  ///
  /// An empty text lacks nothing and is `false`.
  package let isMissingFinalLineBreak: Bool

  /// Decodes `bytes` in `encoding` and drops the encoding's byte order mark if they start with
  /// it, or returns `nil` if the bytes are not valid in `encoding`.
  init?(bytes: Data, encoding: TextEncoding) {
    let byteOrderMark = encoding.byteOrderMark ?? []
    let hasByteOrderMark = !byteOrderMark.isEmpty && bytes.starts(with: byteOrderMark)
    let content = hasByteOrderMark ? bytes.dropFirst(byteOrderMark.count) : bytes
    guard let text = Transcoder.decode(content, from: encoding) else { return nil }
    // Bytes in UTF-8 without a byte order mark are the UTF-8 of the text already. Kept as they
    // are rather than copied, which `Data(content)` does for bytes read from a file, a file that
    // was mapped into memory stays mapped.
    let utf8 =
      encoding == .utf8 ? (hasByteOrderMark ? Data(content) : bytes) : Data(text.utf8)
    let lineEndings = utf8.withUnsafeBytes { LineEndingCounts(utf8: $0) }

    self.encoding = encoding
    self.hasByteOrderMark = hasByteOrderMark
    self.utf8 = utf8
    self.text = text
    self.lineEndingStyle = LineEndingStyle(lineEndings)
    self.isMissingFinalLineBreak =
      utf8.last.map { $0 != ASCII.lineFeed && $0 != ASCII.carriageReturn } ?? false
  }
}
