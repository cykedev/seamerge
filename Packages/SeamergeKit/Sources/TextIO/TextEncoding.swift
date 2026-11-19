import Foundation

/// A text encoding that files are read in and written in.
package enum TextEncoding: Sendable, Hashable, CaseIterable {
  /// UTF-8.
  case utf8

  /// UTF-16 with the less significant byte of each code unit first.
  case utf16LittleEndian

  /// UTF-16 with the more significant byte of each code unit first.
  case utf16BigEndian

  /// UTF-32 with the least significant byte of each code unit first.
  case utf32LittleEndian

  /// UTF-32 with the most significant byte of each code unit first.
  case utf32BigEndian

  /// Windows code page 1252, which extends ISO 8859-1 with printable characters in place of
  /// most C1 control codes.
  case windows1252

  /// ISO 8859-1, which maps every byte to the Unicode scalar of the same value.
  case isoLatin1

  /// Mac OS Roman.
  case macRoman

  /// Whether a file in this encoding can start with a byte order mark.
  ///
  /// Only the Unicode encodings have one.
  package var supportsByteOrderMark: Bool { byteOrderMark != nil }

  /// The bytes of the byte order mark, or `nil` for an encoding without one.
  var byteOrderMark: [UInt8]? {
    switch self {
    case .utf8: [0xEF, 0xBB, 0xBF]
    case .utf16LittleEndian: [0xFF, 0xFE]
    case .utf16BigEndian: [0xFE, 0xFF]
    case .utf32LittleEndian: [0xFF, 0xFE, 0x00, 0x00]
    case .utf32BigEndian: [0x00, 0x00, 0xFE, 0xFF]
    case .windows1252, .isoLatin1, .macRoman: nil
    }
  }

  /// The Foundation encoding for the single-byte encodings, which Foundation converts.
  var singleByteFoundationEncoding: String.Encoding? {
    switch self {
    case .windows1252: .windowsCP1252
    case .isoLatin1: .isoLatin1
    case .macRoman: .macOSRoman
    case .utf8, .utf16LittleEndian, .utf16BigEndian, .utf32LittleEndian, .utf32BigEndian: nil
    }
  }
}
