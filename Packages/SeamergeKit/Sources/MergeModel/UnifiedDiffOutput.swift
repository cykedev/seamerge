import Foundation

/// What a unified diff is written into: its bytes, or its text.
protocol UnifiedDiffOutput {
  /// Appends `line`, a header or a line of its own, and a line feed.
  mutating func append(line: String)

  /// Appends `sign` and `line`, a line of a file read in `encoding` with its line ending, if it
  /// has one; `encoding` is `nil` for a side that does not exist.
  mutating func append(sign: Character, line: Data.SubSequence, in encoding: FileEncoding?)
}

/// A unified diff as bytes, with the lines of each file in its own bytes.
struct ByteOutput: UnifiedDiffOutput {
  private(set) var data = Data()

  mutating func append(line: String) {
    data.append(contentsOf: line.utf8)
    data.append(UInt8(ascii: "\n"))
  }

  mutating func append(sign: Character, line: Data.SubSequence, in encoding: FileEncoding?) {
    data.append(contentsOf: String(sign).utf8)
    data.append(contentsOf: line)
  }
}

/// A unified diff as text, with the lines of each file decoded in the encoding it was read in.
struct DecodedOutput: UnifiedDiffOutput {
  private(set) var text = ""

  mutating func append(line: String) {
    text += line
    text += "\n"
  }

  mutating func append(sign: Character, line: Data.SubSequence, in encoding: FileEncoding?) {
    text.append(sign)
    text += Self.decoded(line, in: encoding ?? .utf8)
  }

  /// `bytes` decoded in `encoding`, with U+FFFD for each byte that is not valid in it.
  ///
  /// A line of a file that was read as text decodes as a whole, since its encoding was
  /// recognized from all its bytes; the replacement is only a fallback.
  private static func decoded(_ bytes: Data.SubSequence, in encoding: FileEncoding) -> String {
    guard let singleByteEncoding = encoding.singleByteStringEncoding else {
      return String(decoding: bytes, as: UTF8.self)
    }
    if let text = String(data: bytes, encoding: singleByteEncoding) {
      return text
    }
    return bytes.map { byte in
      String(data: Data([byte]), encoding: singleByteEncoding) ?? "\u{FFFD}"
    }.joined()
  }
}

extension FileEncoding {
  /// The Foundation encoding of a single-byte encoding, or `nil` for the Unicode encodings.
  fileprivate var singleByteStringEncoding: String.Encoding? {
    switch self {
    case .windows1252: .windowsCP1252
    case .isoLatin1: .isoLatin1
    case .macRoman: .macOSRoman
    case .utf8, .utf16LittleEndian, .utf16BigEndian, .utf32LittleEndian, .utf32BigEndian: nil
    }
  }
}
