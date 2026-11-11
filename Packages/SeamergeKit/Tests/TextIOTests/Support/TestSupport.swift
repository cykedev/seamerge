import Foundation
import Testing
import TextIO

extension LoadedFile {
  /// The decoded text, or `nil` for a binary file.
  var decodedText: DecodedText? {
    if case .text(let text) = content { text } else { nil }
  }
}

extension TextEncoding {
  /// The encodings of Unicode, which have a byte order mark.
  static let unicodeEncodings: [TextEncoding] = [
    .utf8, .utf16LittleEndian, .utf16BigEndian, .utf32LittleEndian, .utf32BigEndian,
  ]

  /// The same encoding in Foundation, which the tests use as an independent encoder.
  var foundationEncoding: String.Encoding {
    switch self {
    case .utf8: .utf8
    case .utf16LittleEndian: .utf16LittleEndian
    case .utf16BigEndian: .utf16BigEndian
    case .utf32LittleEndian: .utf32LittleEndian
    case .utf32BigEndian: .utf32BigEndian
    case .windows1252: .windowsCP1252
    case .isoLatin1: .isoLatin1
    case .macRoman: .macOSRoman
    }
  }

  /// The byte order mark, spelled out independently of the implementation.
  var expectedByteOrderMark: [UInt8] {
    switch self {
    case .utf8: [0xEF, 0xBB, 0xBF]
    case .utf16LittleEndian: [0xFF, 0xFE]
    case .utf16BigEndian: [0xFE, 0xFF]
    case .utf32LittleEndian: [0xFF, 0xFE, 0x00, 0x00]
    case .utf32BigEndian: [0x00, 0x00, 0xFE, 0xFF]
    case .windows1252, .isoLatin1, .macRoman: []
    }
  }

  /// A text with characters beyond ASCII that the encoding can represent.
  var sampleLines: [String] {
    switch self {
    case .utf8, .utf16LittleEndian, .utf16BigEndian, .utf32LittleEndian, .utf32BigEndian:
      ["Grüße aus Zürich", "東京 und 서울", "Emoji: 😀👩‍💻", ""]
    case .windows1252: ["“Grüße” – 5 €", "Œuvre", ""]
    case .isoLatin1: ["Grüße ±½", "Ça va", ""]
    case .macRoman: ["Grüße • π ≠ ∞", "Ça va", ""]
    }
  }
}

extension LineEnding {
  /// The line ending as a string, spelled out independently of the implementation.
  var string: String {
    switch self {
    case .lf: "\n"
    case .crlf: "\r\n"
    case .cr: "\r"
    }
  }
}

/// The bytes of a file holding `text` in `encoding`, produced by Foundation.
func fileBytes(_ text: String, in encoding: TextEncoding, byteOrderMark: Bool = false) throws
  -> Data
{
  let body = try #require(text.data(using: encoding.foundationEncoding))
  return Data(byteOrderMark ? encoding.expectedByteOrderMark : []) + body
}

/// Runs `body` with a new, empty directory that is removed afterwards.
func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
  let directory = FileManager.default.temporaryDirectory
    .appending(path: "TextIOTests-\(UUID().uuidString)", directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: directory) } }
  try body(directory)
}
