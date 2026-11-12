/// The tokens of one line in byte offsets, as the lexers find them from left to right.
struct TokenList {
  private var tokens: [(range: Range<Int>, kind: TokenKind)] = []

  /// Appends a token; one that continues the previous token of the same kind extends it.
  ///
  /// - Precondition: `range` does not start before the end of the previous token.
  mutating func add(_ range: Range<Int>, _ kind: TokenKind) {
    guard !range.isEmpty else { return }
    if let last = tokens.last {
      precondition(last.range.upperBound <= range.lowerBound, "Tokens must not overlap")
      if last.kind == kind, last.range.upperBound == range.lowerBound {
        tokens[tokens.count - 1].range = last.range.lowerBound..<range.upperBound
        return
      }
    }
    tokens.append((range, kind))
  }

  /// The tokens with their ranges converted from UTF-8 bytes to UTF-16 code units.
  ///
  /// - Parameter bytes: The UTF-8 bytes of the line the tokens belong to.
  func utf16Tokens(in bytes: UnsafeBufferPointer<UInt8>) -> [SyntaxToken] {
    guard let end = tokens.last?.range.upperBound else { return [] }
    if !bytes[..<end].contains(where: { $0 >= 0x80 }) {
      return tokens.map { SyntaxToken(range: $0.range, kind: $0.kind) }
    }
    var bytesRead = 0
    var codeUnitsRead = 0
    func utf16Offset(ofByteOffset target: Int) -> Int {
      while bytesRead < target {
        codeUnitsRead += Self.utf16Length(ofScalarStartingWith: bytes[bytesRead])
        bytesRead += 1
      }
      return codeUnitsRead
    }
    return tokens.map { token in
      let lowerBound = utf16Offset(ofByteOffset: token.range.lowerBound)
      let upperBound = utf16Offset(ofByteOffset: token.range.upperBound)
      return SyntaxToken(range: lowerBound..<upperBound, kind: token.kind)
    }
  }

  /// The number of UTF-16 code units of the scalar that a byte begins, or 0 for a byte that
  /// continues a scalar.
  ///
  /// Only scalars beyond the Basic Multilingual Plane, which take four bytes, need two.
  private static func utf16Length(ofScalarStartingWith byte: UInt8) -> Int {
    if byte & 0xC0 == 0x80 { 0 } else if byte >= 0xF0 { 2 } else { 1 }
  }
}
