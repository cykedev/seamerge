/// A `StringSyntax` prepared for lexing: finds where a string opens and how far it goes.
struct StringRule: Sendable {
  /// Where the content of a string starts and the raw delimiter it was opened with.
  struct Opening {
    let contentStart: Int
    let delimiter: [UInt8]
  }

  /// Where scanning the content of a string stopped.
  enum ContentEnd {
    /// The closing delimiter ends before `position`.
    case closed(position: Int)

    /// An interpolation opens before `position`, ended by `close`.
    case interpolation(position: Int, close: UInt8)

    /// The line ends inside the string.
    case lineEnd
  }

  private struct Interpolation {
    /// The opening, without the escape character when it starts with one.
    let open: [UInt8]
    let close: UInt8
  }

  private enum RawDelimiter {
    case repeated(UInt8)
    case parenthesized
  }

  /// The longest raw delimiter taken as one: it bounds the work at each byte of a string and
  /// the size of the lexer state.
  private static let maximumDelimiterLength = 64

  /// Whether the string may continue on the next line.
  let spansLines: Bool

  /// The bytes a string of this form can start with.
  let firstBytes: ByteSet

  private let prefixes: [[UInt8]]
  private let open: [UInt8]
  private let close: [UInt8]
  private let escape: UInt8?
  private let escapesByDoubling: Bool
  private let rawDelimiter: RawDelimiter?
  private let escapedInterpolations: [Interpolation]
  private let plainInterpolations: [Interpolation]
  private let isCharacterLiteral: Bool

  init(_ syntax: StringSyntax) {
    precondition(!syntax.open.isEmpty && !syntax.close.isEmpty, "String delimiters are empty")
    spansLines = syntax.spansLines
    prefixes = syntax.prefixes.map { Array($0.lowercased().utf8) }
    open = Array(syntax.open.utf8)
    close = Array(syntax.close.utf8)
    let escape: UInt8? = syntax.escape == .backslash ? UInt8(ascii: "\\") : nil
    self.escape = escape
    escapesByDoubling = syntax.escape == .doubledDelimiter
    let rawDelimiter: RawDelimiter?
    switch syntax.rawDelimiter {
    case .repeated(let character)?:
      guard let byte = character.asciiValue else {
        preconditionFailure("A repeated raw delimiter must be an ASCII character")
      }
      rawDelimiter = .repeated(byte)
    case .parenthesized?:
      rawDelimiter = .parenthesized
    case nil:
      rawDelimiter = nil
    }
    self.rawDelimiter = rawDelimiter
    let interpolations = syntax.interpolations.map { interpolation in
      let close = Array(String(interpolation.close).utf8)
      precondition(close.count == 1, "An interpolation must close with one ASCII character")
      return Interpolation(open: Array(interpolation.open.utf8), close: close[0])
    }
    escapedInterpolations = interpolations.filter { $0.open.first == escape }.map {
      Interpolation(open: Array($0.open.dropFirst()), close: $0.close)
    }
    plainInterpolations = interpolations.filter { $0.open.first != escape }
    isCharacterLiteral = syntax.isCharacterLiteral

    var firstBytes = ByteSet()
    for prefix in syntax.prefixes {
      let first = prefix.first ?? syntax.open.first
      if case .repeated(let byte)? = rawDelimiter, prefix.isEmpty { firstBytes.insert(byte) }
      for character in [first?.lowercased(), first?.uppercased()].compactMap({ $0 }) {
        firstBytes = firstBytes.union(ByteSet(character))
      }
    }
    self.firstBytes = firstBytes
  }

  /// The opening of a string of this form at a position, if one starts there.
  func opening(in line: LineBytes, at position: Int) -> Opening? {
    for prefix in prefixes where line.hasPrefix(lowercased: prefix, at: position) {
      guard let opening = openingAfterPrefix(in: line, at: position + prefix.count) else {
        continue
      }
      if isCharacterLiteral, !holdsOneCharacter(line, from: opening.contentStart) { continue }
      return opening
    }
    return nil
  }

  private func openingAfterPrefix(in line: LineBytes, at position: Int) -> Opening? {
    switch rawDelimiter {
    case nil:
      guard line.hasPrefix(open, at: position) else { return nil }
      return Opening(contentStart: position + open.count, delimiter: [])
    case .repeated(let byte)?:
      var delimiterEnd = position
      while line.byte(at: delimiterEnd) == byte,
        delimiterEnd - position <= Self.maximumDelimiterLength
      {
        delimiterEnd += 1
      }
      let length = delimiterEnd - position
      guard length <= Self.maximumDelimiterLength, line.hasPrefix(open, at: delimiterEnd) else {
        return nil
      }
      return Opening(
        contentStart: delimiterEnd + open.count,
        delimiter: [UInt8](repeating: byte, count: length))
    case .parenthesized?:
      guard line.hasPrefix(open, at: position) else { return nil }
      let delimiterStart = position + open.count
      var delimiterEnd = delimiterStart
      while let byte = line.byte(at: delimiterEnd), Self.isParenthesizedDelimiterByte(byte),
        delimiterEnd - delimiterStart < Self.maximumDelimiterLength
      {
        delimiterEnd += 1
      }
      guard line.byte(at: delimiterEnd) == UInt8(ascii: "(") else { return nil }
      return Opening(
        contentStart: delimiterEnd + 1, delimiter: line.bytes(in: delimiterStart..<delimiterEnd))
    }
  }

  /// Scans the content of a string from a position to its end, the next interpolation or the
  /// end of the line.
  func scanContent(in line: LineBytes, from position: Int, delimiter: [UInt8]) -> ContentEnd {
    let closing = closing(for: delimiter)
    // In Swift's raw strings the escape character is followed by the raw delimiter.
    let escapeDelimiter: [UInt8] =
      if case .repeated? = rawDelimiter { delimiter } else { [] }
    var position = position
    scanning: while position < line.count {
      let byte = line[position]
      if byte == closing[0], line.hasPrefix(closing, at: position) {
        if escapesByDoubling, line.hasPrefix(closing, at: position + closing.count) {
          position += 2 * closing.count
          continue
        }
        return .closed(position: position + closing.count)
      }
      if byte == escape, line.hasPrefix(escapeDelimiter, at: position + 1) {
        let escaped = position + 1 + escapeDelimiter.count
        for interpolation in escapedInterpolations
        where line.hasPrefix(interpolation.open, at: escaped) {
          return .interpolation(
            position: escaped + interpolation.open.count, close: interpolation.close)
        }
        position = escaped + 1
        continue
      }
      for interpolation in plainInterpolations
      where byte == interpolation.open[0] && line.hasPrefix(interpolation.open, at: position) {
        if interpolation.open.count == 1, line.byte(at: position + 1) == byte {
          position += 2
          continue scanning
        }
        return .interpolation(
          position: position + interpolation.open.count, close: interpolation.close)
      }
      position += 1
    }
    return .lineEnd
  }

  private func closing(for delimiter: [UInt8]) -> [UInt8] {
    switch rawDelimiter {
    case nil: close
    case .repeated?: delimiter.isEmpty ? close : close + delimiter
    case .parenthesized?: [UInt8(ascii: ")")] + delimiter + close
    }
  }

  /// Whether a character literal’s content from a position is one escape or one character,
  /// followed by the closing delimiter.
  private func holdsOneCharacter(_ line: LineBytes, from position: Int) -> Bool {
    guard let first = line.byte(at: position) else { return false }
    if first == escape {
      guard let end = line.firstPosition(of: close[0], from: position + 2) else { return false }
      return line.hasPrefix(close, at: end)
    }
    return line.hasPrefix(close, at: position + Self.utf8Length(ofScalarStartingWith: first))
  }

  private static func utf8Length(ofScalarStartingWith byte: UInt8) -> Int {
    if byte >= 0xF0 { 4 } else if byte >= 0xE0 { 3 } else if byte >= 0xC0 { 2 } else { 1 }
  }

  /// Whether a byte may be part of the word of a C++ raw string, which excludes spaces,
  /// parentheses and the backslash.
  private static func isParenthesizedDelimiterByte(_ byte: UInt8) -> Bool {
    byte > UInt8(ascii: " ") && byte < 0x7F && byte != UInt8(ascii: "(")
      && byte != UInt8(ascii: ")") && byte != UInt8(ascii: "\\")
  }
}
