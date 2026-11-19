/// A colored stretch of one line.
package struct SyntaxToken: Sendable, Hashable {
  /// The stretch in UTF-16 code units, counted from the start of the line.
  package let range: Range<Int>

  /// What the stretch is.
  package let kind: TokenKind
}
