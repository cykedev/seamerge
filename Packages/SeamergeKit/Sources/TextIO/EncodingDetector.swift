import Foundation

/// Recognizes whether bytes are text and in which encoding.
enum EncodingDetector {
  /// The number of leading bytes that are searched for a NUL byte to recognize a binary file.
  static let binaryProbeLength = 8192

  /// The encodings with a byte order mark, in the order they are tried.
  ///
  /// UTF-32 comes before UTF-16 because the UTF-32 little-endian mark begins with the UTF-16 one.
  private static let byteOrderMarkEncodings: [TextEncoding] = [
    .utf32LittleEndian, .utf32BigEndian, .utf8, .utf16LittleEndian, .utf16BigEndian,
  ]

  /// The encodings tried for bytes that are neither marked nor valid UTF-8, most preferred first.
  ///
  /// ISO 8859-1 accepts every byte.
  private static let singleByteEncodings: [TextEncoding] = [.windows1252, .isoLatin1, .macRoman]

  /// Recognizes the content of `bytes` in the order described at
  /// ``LoadedFile/init(bytes:encoding:)``.
  static func content(of bytes: Data) -> LoadedFile.Content {
    for encoding in byteOrderMarkEncodings
    where encoding.byteOrderMark.map(bytes.starts(with:)) == true {
      if let text = DecodedText(bytes: bytes, encoding: encoding) { return .text(text) }
    }
    if bytes.prefix(binaryProbeLength).contains(0) { return .binary }
    if let text = DecodedText(bytes: bytes, encoding: .utf8) { return .text(text) }

    let suggested = suggestedSingleByteEncoding(for: bytes)
    for encoding in [suggested].compactMap(\.self) + singleByteEncodings {
      if let text = DecodedText(bytes: bytes, encoding: encoding) { return .text(text) }
    }
    preconditionFailure("ISO 8859-1 decodes every byte sequence")
  }

  /// The single-byte encoding that Foundation's statistical detection picks for `bytes`.
  ///
  /// Foundation finds none for some inputs, such as a lone byte that Windows-1252 leaves
  /// undefined, so the caller falls back to a fixed order.
  private static func suggestedSingleByteEncoding(for bytes: Data) -> TextEncoding? {
    let candidates = singleByteEncodings.compactMap(\.singleByteFoundationEncoding)
    let detected = NSString.stringEncoding(
      for: bytes,
      encodingOptions: [
        .suggestedEncodingsKey: candidates.map(\.rawValue),
        .useOnlySuggestedEncodingsKey: true,
        .allowLossyKey: false,
      ],
      convertedString: nil,
      usedLossyConversion: nil
    )
    return singleByteEncodings.first { $0.singleByteFoundationEncoding?.rawValue == detected }
  }
}
