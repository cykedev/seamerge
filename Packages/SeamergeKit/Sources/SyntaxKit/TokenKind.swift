/// What a colored stretch of text is.
///
/// Syntax coloring is deliberately restrained: only these four kinds get a color of their own,
/// everything else keeps the color of plain text.
public enum TokenKind: Sendable, Hashable {
  /// A line or block comment, including its delimiters.
  case comment

  /// A string or character literal, including its delimiters and prefixes.
  ///
  /// The code inside an interpolation is not part of the string.
  case string

  /// A numeric literal, including its prefix and suffix, such as `0x1F` or `2.5f`.
  case number

  /// A reserved word of the language, or a directive such as `#if` or `@media`.
  case keyword
}
