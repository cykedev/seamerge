extension LanguageDescription {
  /// Rust, with nested block comments, raw strings, and character literals told apart from
  /// lifetimes.
  static let rust = LanguageDescription(
    name: "Rust", fileExtensions: ["rs"],
    syntax: .code(
      CodeSyntax(
        keywords: [
          "as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum",
          "extern", "false", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod",
          "move", "mut", "pub", "ref", "return", "self", "Self", "static", "struct", "super",
          "trait", "true", "type", "unsafe", "use", "where", "while",
        ],
        lineComments: ["//"],
        blockComments: [BlockCommentSyntax(open: "/*", close: "*/", nests: true)],
        strings: [
          StringSyntax(
            "\"", prefixes: ["r", "br", "cr"], escape: .noEscapes, spansLines: true,
            rawDelimiter: .repeated("#")),
          StringSyntax("\"", prefixes: ["", "b", "c"], spansLines: true),
          StringSyntax("'", prefixes: ["", "b"], isCharacterLiteral: true),
        ])))
}
