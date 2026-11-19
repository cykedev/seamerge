/// A stretch of a line that the pane colors by what it is in the code.
package struct PaneToken: Sendable, Hashable {
  /// What a stretch of code is, which decides its color.
  package enum Kind: Sendable, Hashable, CaseIterable {
    /// A reserved word of the language, or a directive.
    case keyword

    /// A string or character literal.
    case string

    /// A numeric literal, colored as strings are.
    case number

    /// A line or block comment.
    case comment
  }

  /// The stretch in UTF-16 code units, counted from the start of the line.
  package var range: Range<Int>

  /// What the stretch is.
  package var kind: Kind

  /// Creates a token of `kind` over `range` of its line.
  package init(range: Range<Int>, kind: Kind) {
    self.range = range
    self.kind = kind
  }
}
