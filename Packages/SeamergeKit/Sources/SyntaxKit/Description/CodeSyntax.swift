/// The syntax of a programming language, as read by the lexer for code.
struct CodeSyntax: Sendable, Hashable {
  /// The reserved words.
  var keywords: [String]

  /// Whether keywords match regardless of case, as in SQL.
  var keywordsIgnoreCase = false

  /// The characters that start a comment running to the end of the line.
  var lineComments: [String] = []

  /// Whether a line comment starts only at the beginning of a word, as `#` in a shell, where
  /// `$#` and `a#b` are no comments.
  var lineCommentsStartWords = false

  /// The forms of block comments.
  var blockComments: [BlockCommentSyntax] = []

  /// The forms of string and character literals, in the order they are tried.
  var strings: [StringSyntax] = []

  /// Here documents, if the language has them.
  var hereDocuments: HereDocumentSyntax?

  /// Characters that make a keyword of any word they start, such as `@` and `#` in Swift.
  var keywordPrefixes = ""

  /// Characters that start a word that is never a keyword, such as `$` in PHP.
  var variablePrefixes = ""

  /// Characters that belong to a word besides letters, digits and the underscore, such as `-`
  /// in CSS.
  var wordCharacters = ""

  /// Characters that separate the digits of a number besides the underscore, such as `'` in
  /// C++.
  var digitSeparators = ""
}

/// How one form of block comment is written.
struct BlockCommentSyntax: Sendable, Hashable {
  /// The opening delimiter.
  let open: String

  /// The closing delimiter.
  let close: String

  /// Whether comments of this form nest, as in Swift and Rust.
  let nests: Bool

  /// Whether both delimiters count only at the start of a line, as Ruby’s `=begin` and
  /// `=end`.
  ///
  /// The lines in between are comment as a whole.
  let standsOnOwnLines: Bool

  init(open: String, close: String, nests: Bool = false, standsOnOwnLines: Bool = false) {
    self.open = open
    self.close = close
    self.nests = nests
    self.standsOnOwnLines = standsOnOwnLines
  }
}

/// How here documents are written: an introducer and a word, such as `<<EOF`, then lines of
/// text up to a line holding only the word.
///
/// The text starts on the line after the introducer; the rest of that line is code. The word
/// may be quoted, and the line that ends the text may indent it and continue after it with
/// punctuation, as PHP allows.
struct HereDocumentSyntax: Sendable, Hashable {
  /// The introducers, longest first, such as `<<-` and `<<`.
  let introducers: [String]

  /// Whether spaces may stand between the introducer and the word, as in a shell.
  let allowsSpaceBeforeWord: Bool
}
