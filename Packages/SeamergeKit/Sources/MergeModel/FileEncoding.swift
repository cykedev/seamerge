import TextIO

/// The text encoding a file was read in.
public enum FileEncoding: Sendable, Hashable, CaseIterable {
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

  /// Windows code page 1252.
  case windows1252

  /// ISO 8859-1.
  case isoLatin1

  /// Mac OS Roman.
  case macRoman

  /// The encoding as TextIO describes it.
  init(_ encoding: TextEncoding) {
    self =
      switch encoding {
      case .utf8: .utf8
      case .utf16LittleEndian: .utf16LittleEndian
      case .utf16BigEndian: .utf16BigEndian
      case .utf32LittleEndian: .utf32LittleEndian
      case .utf32BigEndian: .utf32BigEndian
      case .windows1252: .windows1252
      case .isoLatin1: .isoLatin1
      case .macRoman: .macRoman
      }
  }

  /// The encoding as TextIO describes it.
  var textEncoding: TextEncoding {
    switch self {
    case .utf8: .utf8
    case .utf16LittleEndian: .utf16LittleEndian
    case .utf16BigEndian: .utf16BigEndian
    case .utf32LittleEndian: .utf32LittleEndian
    case .utf32BigEndian: .utf32BigEndian
    case .windows1252: .windows1252
    case .isoLatin1: .isoLatin1
    case .macRoman: .macRoman
    }
  }

  /// Whether a file in this encoding can start with a byte order mark; only the Unicode
  /// encodings have one.
  public var supportsByteOrderMark: Bool { textEncoding.supportsByteOrderMark }
}
