import Foundation
import TextIO

/// A file that a session compares: its name, its bytes and its text.
///
/// The encoding is recognized when the file is read. The text keeps the line endings of the
/// file; how it is split into lines depends on the comparison mode and is decided by the session.
public struct SourceFile: Sendable {
  /// The name shown for the file.
  public let label: String

  /// Where the file was read from, if it was read from disk.
  public let url: URL?

  /// The bytes of the file, exactly as read.
  public let bytes: Data

  /// The decoded text, or `nil` if the file is binary.
  let decodedText: DecodedText?

  /// The text as UTF-8 with the first byte at index 0, as the engine and the line index expect
  /// it, or `nil` if the file is binary.
  let utf8: Data?

  /// Reads the file at `url` and recognizes its encoding.
  ///
  /// The file is memory-mapped where that is safe. Reading and decoding take time in proportion
  /// to the size of the file, so large files are best read off the main thread.
  ///
  /// - Throws: The error of the file system if the file cannot be read.
  public init(contentsOf url: URL, label: String) throws {
    try self.init(bytes: Data(contentsOf: url, options: .mappedIfSafe), label: label, url: url)
  }

  /// Creates a file from its bytes and recognizes their encoding.
  public init(bytes: Data, label: String, url: URL? = nil) {
    let loaded: LoadedFile
    do {
      loaded = try LoadedFile(bytes: bytes)
    } catch {
      preconditionFailure("Recognizing the encoding of bytes never fails: \(error)")
    }
    self.label = label
    self.url = url
    self.bytes = bytes
    switch loaded.content {
    case .text(let text):
      decodedText = text
      utf8 = text.utf8.startIndex == 0 ? text.utf8 : Data(text.utf8)
    case .binary:
      decodedText = nil
      utf8 = nil
    }
  }

  /// Whether the file is binary and has no text to compare.
  public var isBinary: Bool { decodedText == nil }

  /// The text of the file with its line endings, or `nil` if the file is binary.
  public var text: String? { decodedText?.text }

  /// The encoding the file was read in, or `nil` if the file is binary.
  public var encoding: FileEncoding? {
    decodedText.map { FileEncoding($0.encoding) }
  }

  /// Whether the file starts with the byte order mark of its encoding; `false` for a binary
  /// file.
  public var hasByteOrderMark: Bool { decodedText?.hasByteOrderMark ?? false }

  /// The line ending that ends most lines of the text, or `nil` if the file is binary or has
  /// no line break.
  ///
  /// A tie goes to LF, then to CRLF, before CR.
  public var predominantLineEnding: ResultFormat.LineEnding? {
    decodedText?.lineEndingStyle.map { ResultFormat.LineEnding($0.predominantLineEnding) }
  }

  /// How the lines of the text end, or `nil` if the file is binary or has no line break.
  public var lineEndings: LineEndings? {
    decodedText?.lineEndingStyle.map(LineEndings.init)
  }

  /// The UTF-8 text as a comparison in `mode` sees it, or `nil` if the file is binary.
  ///
  /// The exact mode ends lines only at LF, so a file whose lines all end in CR would be a single
  /// line; its CRs become LFs for the comparison. Both are one byte long, so every offset stays
  /// the same, and the file itself keeps its line endings. A lone CR in a file with other line
  /// endings stays as it is.
  func comparedText(in mode: ComparisonMode) -> Data? {
    guard let utf8 else { return nil }
    guard mode == .exact, decodedText?.lineEndingStyle == .uniform(.cr) else { return utf8 }
    return Data(utf8.map { $0 == UInt8(ascii: "\r") ? UInt8(ascii: "\n") : $0 })
  }
}
