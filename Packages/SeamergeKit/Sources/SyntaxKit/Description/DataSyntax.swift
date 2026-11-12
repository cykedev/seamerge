/// The syntax of a data format, as read by the lexer for data.
///
/// Data is lexed as a sequence of scalars. A quote starts a string only where a scalar starts,
/// so the apostrophe in YAML’s `title: Don't panic` is plain text. A plain scalar is colored
/// as a number or keyword only when it is one as a whole.
struct DataSyntax: Sendable, Hashable {
  /// The words that are literal values, such as `true` and `null`, each in every spelling
  /// that counts.
  let keywords: [String]

  /// The characters that start a comment running to the end of the line.
  let lineComments: [String]

  /// Whether a comment needs a space or the start of the line before it, as in YAML.
  let commentsNeedPrecedingSpace: Bool

  /// The forms of strings, in the order they are tried.
  let strings: [StringSyntax]

  /// The character between a key and its value.
  let keyValueSeparator: Character

  /// Whether the separator needs a space or the end of the line after it, as in YAML, where
  /// `a:b` is a plain scalar.
  ///
  /// Right after a quoted key it never does.
  let separatorNeedsSpace: Bool

  /// The character that starts an entry of a sequence when a space follows, as `-` in YAML.
  let sequenceIndicator: Character?

  /// The characters that introduce a block scalar, as `|` and `>` in YAML: the more indented
  /// lines that follow are a string.
  let blockScalarIndicators: [Character]
}
