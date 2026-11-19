import Foundation

/// A file as read from disk: its bytes and, unless it is binary, its decoded text.
package struct LoadedFile: Sendable {
  /// What a file holds.
  package enum Content: Sendable {
    /// Text in a recognized encoding.
    case text(DecodedText)

    /// Bytes that are not compared as text.
    case binary
  }

  /// The bytes of the file, exactly as they are on disk.
  package let bytes: Data

  /// The decoded text, or the verdict that the file is binary.
  package let content: Content

  /// Whether the file is binary and has no text.
  package var isBinary: Bool {
    if case .binary = content { true } else { false }
  }

  /// Reads the file at `url`.
  ///
  /// The file is memory-mapped where that is safe. See ``init(bytes:encoding:)`` for how its
  /// content is recognized.
  ///
  /// - Parameters:
  ///   - url: The location of a file.
  ///   - encoding: The encoding to read the file in, or `nil` to recognize it.
  /// - Throws: ``TextIOError/invalidBytes(_:)`` if the file is not valid in `encoding`, or the
  ///   error of the file system if the file cannot be read.
  package init(contentsOf url: URL, encoding: TextEncoding? = nil) throws {
    try self.init(bytes: Data(contentsOf: url, options: .mappedIfSafe), encoding: encoding)
  }

  /// Recognizes the content of `bytes`, or decodes them in the given encoding.
  ///
  /// Without a given encoding, the first of these that applies decides:
  /// 1. A byte order mark of UTF-8, UTF-16 or UTF-32 that the rest of the bytes are valid in.
  /// 2. A NUL byte in the first 8 KiB makes the bytes binary.
  /// 3. Valid UTF-8.
  /// 4. Windows-1252, ISO 8859-1 or Mac OS Roman, as Foundation's detection suggests. ISO 8859-1
  ///    accepts every byte, so this step always succeeds.
  ///
  /// With a given encoding, the bytes are decoded in it and are never binary; a byte order mark of
  /// that encoding is recognized and dropped.
  ///
  /// - Parameters:
  ///   - bytes: The content of a file.
  ///   - encoding: The encoding to decode the bytes in, or `nil` to recognize it.
  /// - Throws: ``TextIOError/invalidBytes(_:)`` if the bytes are not valid in `encoding`.
  package init(bytes: Data, encoding: TextEncoding? = nil) throws(TextIOError) {
    self.bytes = bytes
    if let encoding {
      guard let text = DecodedText(bytes: bytes, encoding: encoding) else {
        throw .invalidBytes(encoding)
      }
      content = .text(text)
    } else {
      content = EncodingDetector.content(of: bytes)
    }
  }
}
