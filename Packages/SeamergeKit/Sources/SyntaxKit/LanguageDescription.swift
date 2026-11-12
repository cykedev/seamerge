/// A language that SyntaxKit can color: how its files are recognized and how its text is
/// written.
///
/// A description is a value. Its syntax is a table for one of three lexer families, so that
/// adding a language means adding a table, not code.
public struct LanguageDescription: Sendable, Hashable {
  /// The syntax of a language, as a table for the lexer of its family.
  enum Syntax: Sendable, Hashable {
    /// A programming language such as Swift, Python or SQL, and style sheets.
    case code(CodeSyntax)

    /// A markup language such as HTML, XML or Markdown.
    case markup(MarkupSyntax)

    /// A data format such as JSON, YAML or TOML.
    case data(DataSyntax)

    /// Text without syntax; nothing is colored.
    case plainText
  }

  /// The name of the language, such as “Swift” or “C++”.
  public let name: String

  /// The file name extensions, in lowercase and without the dot.
  let fileExtensions: [String]

  /// Whole file names that identify the language regardless of their extension, such as
  /// `Gemfile`.
  let fileNames: [String]

  /// The interpreters a `#!` line names for scripts in this language, without a version
  /// number, such as `python` for `python3.12`.
  let interpreters: [String]

  /// How text in the language is written.
  let syntax: Syntax

  init(
    name: String, fileExtensions: [String], fileNames: [String] = [],
    interpreters: [String] = [], syntax: Syntax
  ) {
    self.name = name
    self.fileExtensions = fileExtensions
    self.fileNames = fileNames
    self.interpreters = interpreters
    self.syntax = syntax
  }

  /// Text without syntax, for files of an unknown language; lexing it yields no tokens.
  public static let plainText = LanguageDescription(
    name: "Plain Text", fileExtensions: ["txt"], syntax: .plainText)
}
