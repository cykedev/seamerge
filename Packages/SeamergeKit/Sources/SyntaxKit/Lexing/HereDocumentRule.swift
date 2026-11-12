/// A `HereDocumentSyntax` prepared for lexing: finds introducers and the line that ends the
/// text.
struct HereDocumentRule: Sendable {
  /// An introducer with its word, and where it ends on the line.
  struct Introduction {
    let end: Int
    let terminator: [UInt8]
  }

  /// The longest word taken as a terminator, which bounds the size of the lexer state.
  private static let maximumWordLength = 64

  /// The bytes an introducer can start with.
  let firstBytes: ByteSet

  private let introducers: [[UInt8]]
  private let allowsSpaceBeforeWord: Bool

  init(_ syntax: HereDocumentSyntax) {
    introducers = syntax.introducers.map { Array($0.utf8) }
    precondition(!introducers.contains(where: \.isEmpty), "An introducer must not be empty")
    allowsSpaceBeforeWord = syntax.allowsSpaceBeforeWord
    firstBytes = ByteSet(syntax.introducers.compactMap(\.first))
  }

  /// The introducer and word of a here document at a position, if one starts there.
  func introduction(in line: LineBytes, at position: Int) -> Introduction? {
    for introducer in introducers where line.hasPrefix(introducer, at: position) {
      // A longer run of the introducer's character, as `<<<` in a shell, is something else.
      if position > 0, line[position - 1] == introducer[0] { return nil }
      var wordStart = position + introducer.count
      if allowsSpaceBeforeWord { wordStart = line.skippingSpaces(from: wordStart) }
      var quote: UInt8?
      if let byte = line.byte(at: wordStart),
        byte == UInt8(ascii: "'") || byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "\\")
      {
        quote = byte == UInt8(ascii: "\\") ? nil : byte
        wordStart += 1
      }
      guard let first = line.byte(at: wordStart), first.isASCIILetter || first == .underscore
      else { return nil }
      var wordEnd = wordStart + 1
      while let byte = line.byte(at: wordEnd), ByteSet.asciiWordCharacters.contains(byte) {
        wordEnd += 1
      }
      guard wordEnd - wordStart <= Self.maximumWordLength else { return nil }
      var end = wordEnd
      if let quote {
        guard line.byte(at: wordEnd) == quote else { return nil }
        end += 1
      }
      return Introduction(end: end, terminator: line.bytes(in: wordStart..<wordEnd))
    }
    return nil
  }

  /// Whether a line ends the here document whose word is `terminator`.
  func isTerminator(_ terminator: [UInt8], _ line: LineBytes) -> Bool {
    let start = line.skippingSpaces(from: 0)
    guard line.hasPrefix(terminator, at: start) else { return false }
    guard let next = line.byte(at: start + terminator.count) else { return true }
    return !ByteSet.asciiWordCharacters.contains(next)
  }
}
