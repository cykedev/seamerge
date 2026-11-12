/// A colored stretch of one line.
public struct SyntaxToken: Sendable, Hashable {
  /// The stretch in UTF-16 code units, counted from the start of the line.
  public let range: Range<Int>

  /// What the stretch is.
  public let kind: TokenKind
}
