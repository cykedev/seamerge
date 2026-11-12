/// How one form of string or character literal is written.
///
/// A language lists its forms in the order they are tried, so a form whose opening begins with
/// another one's, like `"""` and `"`, comes first.
struct StringSyntax: Sendable, Hashable {
  /// How a delimiter is written inside the string without ending it.
  enum Escape: Sendable, Hashable {
    /// Nothing can be escaped; the first closing delimiter ends the string.
    case noEscapes

    /// A backslash escapes the character after it.
    case backslash

    /// The closing delimiter written twice stands for itself, as in SQL’s `'it''s'`.
    case doubledDelimiter
  }

  /// An extra delimiter of raw strings, chosen anew for each string.
  enum RawDelimiter: Sendable, Hashable {
    /// Any number of this character before the opening and after the closing delimiter, as
    /// in Swift’s `#"…"#` and Rust’s `r#"…"#`.
    ///
    /// In Swift the same number of them follows the backslash of an escape, so `\#n` is an
    /// escape in `#"…"#` and `\n` is not.
    case repeated(Character)

    /// A word in parentheses inside the delimiters, as in C++’s `R"word(…)word"`.
    case parenthesized
  }

  /// Code inside a string whose value is put into the string, such as Swift’s `\(name)`.
  struct Interpolation: Sendable, Hashable {
    /// The characters that start the code, such as `\(` or `${`.
    ///
    /// A one-character opening written twice, as in `{{`, is a literal character instead.
    let open: String

    /// The bracket that ends the code; brackets of its kind inside the code are counted.
    let close: Character
  }

  /// Letters that may stand right before the opening delimiter and belong to the string, such
  /// as `r` or `f` in Python.
  ///
  /// The empty prefix stands for the delimiter alone. Prefixes match regardless of case.
  let prefixes: [String]

  /// The opening delimiter.
  let open: String

  /// The closing delimiter.
  let close: String

  /// How the closing delimiter is escaped.
  let escape: Escape

  /// Whether the string may continue on the next line.
  ///
  /// A string that may not ends with its line even when its closing delimiter is missing.
  let spansLines: Bool

  /// The extra delimiter of raw strings, if this form has one.
  let rawDelimiter: RawDelimiter?

  /// The kinds of interpolation the string contains.
  let interpolations: [Interpolation]

  /// Whether the literal holds exactly one character or one escape, as Rust’s `'a'`.
  ///
  /// An opening delimiter that is not followed by such a literal is taken as plain text, so
  /// Rust’s lifetimes such as `'a` are not taken for the start of a literal.
  let isCharacterLiteral: Bool

  init(
    _ open: String, close: String? = nil, prefixes: [String] = [""],
    escape: Escape = .backslash, spansLines: Bool = false, rawDelimiter: RawDelimiter? = nil,
    interpolations: [Interpolation] = [], isCharacterLiteral: Bool = false
  ) {
    self.open = open
    self.close = close ?? open
    self.prefixes = prefixes
    self.escape = escape
    self.spansLines = spansLines
    self.rawDelimiter = rawDelimiter
    self.interpolations = interpolations
    self.isCharacterLiteral = isCharacterLiteral
  }
}
