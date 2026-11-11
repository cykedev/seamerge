import Foundation

/// The text of a file, decoded, together with what is needed to write it back in the same form.
public struct DecodedText: Sendable {
  /// The encoding the file is in.
  public let encoding: TextEncoding

  /// Whether the file starts with the byte order mark of ``encoding``.
  public let hasByteOrderMark: Bool

  /// The text as UTF-8, without a byte order mark and with line endings as they are in the file.
  public let utf8: Data

  /// The text, with line endings as they are in the file.
  public let text: String

  /// The line endings of the text, or `nil` if it has no line break.
  public let lineEndingStyle: LineEndingStyle?

  /// Whether the text has characters after its last line break, so that its last line has no
  /// line ending.
  ///
  /// An empty text lacks nothing and is `false`.
  public let isMissingFinalLineBreak: Bool

  /// Decodes `bytes` in `encoding` and drops the encoding's byte order mark if they start with
  /// it, or returns `nil` if the bytes are not valid in `encoding`.
  init?(bytes: Data, encoding: TextEncoding) {
    let byteOrderMark = encoding.byteOrderMark ?? []
    let hasByteOrderMark = !byteOrderMark.isEmpty && bytes.starts(with: byteOrderMark)
    let content = hasByteOrderMark ? bytes.dropFirst(byteOrderMark.count) : bytes
    guard let text = Transcoder.decode(content, from: encoding) else { return nil }
    let utf8 = encoding == .utf8 ? Data(content) : Data(text.utf8)
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
