import Foundation

/// Converts between bytes in a ``TextEncoding`` and Swift strings without losing anything.
///
/// Every conversion is strict: a byte sequence that is not valid in the encoding, or a character
/// the encoding cannot represent, makes the conversion fail instead of being replaced.
enum Transcoder {
  /// Decodes `bytes`, which hold no byte order mark, or returns `nil` if they are not valid in
  /// `encoding`.
  ///
  /// A single-byte encoding only succeeds if encoding the text again gives back the same bytes, so
  /// that writing an unchanged file reproduces it exactly.
  static func decode(_ bytes: Data, from encoding: TextEncoding) -> String? {
    switch encoding {
    case .utf8:
      return String(validating: bytes, as: UTF8.self)
    case .utf16LittleEndian:
      return decode(bytes, as: UTF16.self, bigEndian: false)
    case .utf16BigEndian:
      return decode(bytes, as: UTF16.self, bigEndian: true)
    case .utf32LittleEndian:
      return decode(bytes, as: UTF32.self, bigEndian: false)
    case .utf32BigEndian:
      return decode(bytes, as: UTF32.self, bigEndian: true)
    case .windows1252, .isoLatin1, .macRoman:
      guard let foundationEncoding = encoding.singleByteFoundationEncoding,
        let text = String(data: bytes, encoding: foundationEncoding),
        text.data(using: foundationEncoding, allowLossyConversion: false) == bytes
      else { return nil }
      return text
    }
  }

  /// Encodes UTF-8 encoded text, which must be valid, without a byte order mark, or returns `nil`
  /// if `encoding` cannot represent every character.
  static func encode(utf8 text: [UInt8], to encoding: TextEncoding) -> [UInt8]? {
    switch encoding {
    case .utf8:
      return text
    case .utf16LittleEndian:
      return encode(utf8: text, as: UTF16.self, bigEndian: false)
    case .utf16BigEndian:
      return encode(utf8: text, as: UTF16.self, bigEndian: true)
    case .utf32LittleEndian:
      return encode(utf8: text, as: UTF32.self, bigEndian: false)
    case .utf32BigEndian:
      return encode(utf8: text, as: UTF32.self, bigEndian: true)
    case .windows1252, .isoLatin1, .macRoman:
      guard let foundationEncoding = encoding.singleByteFoundationEncoding,
        let bytes = String(decoding: text, as: UTF8.self).data(
          using: foundationEncoding, allowLossyConversion: false)
      else { return nil }
      return [UInt8](bytes)
    }
  }

  private static func decode<Encoding: Unicode.Encoding>(
    _ bytes: Data, as encoding: Encoding.Type, bigEndian: Bool
  ) -> String? where Encoding.CodeUnit: FixedWidthInteger {
    let width = MemoryLayout<Encoding.CodeUnit>.size
    guard bytes.count.isMultiple(of: width) else { return nil }
    let codeUnits = bytes.withUnsafeBytes { buffer in
      (0..<buffer.count / width).map { index in
        let stored = buffer.loadUnaligned(fromByteOffset: index * width, as: Encoding.CodeUnit.self)
        return bigEndian
          ? Encoding.CodeUnit(bigEndian: stored) : Encoding.CodeUnit(littleEndian: stored)
      }
    }
    return String(validating: codeUnits, as: Encoding.self)
  }

  private static func encode<Encoding: Unicode.Encoding>(
    utf8 text: [UInt8], as encoding: Encoding.Type, bigEndian: Bool
  ) -> [UInt8] where Encoding.CodeUnit: FixedWidthInteger {
    var bytes: [UInt8] = []
    bytes.reserveCapacity(text.count * MemoryLayout<Encoding.CodeUnit>.size)
    // Valid UTF-8 always transcodes to UTF-16 and UTF-32, so the result cannot report an error.
    _ = transcode(text.makeIterator(), from: UTF8.self, to: encoding, stoppingOnError: true) {
      codeUnit in
      withUnsafeBytes(of: bigEndian ? codeUnit.bigEndian : codeUnit.littleEndian) {
        bytes.append(contentsOf: $0)
      }
    }
    return bytes
  }
}
