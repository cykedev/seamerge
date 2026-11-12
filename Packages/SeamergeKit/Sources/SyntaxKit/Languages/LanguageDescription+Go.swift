extension LanguageDescription {
  /// Go, with raw strings in backquotes.
  static let go = LanguageDescription(
    name: "Go", fileExtensions: ["go"],
    syntax: .code(
      CodeSyntax(
        keywords: [
          "break", "case", "chan", "const", "continue", "default", "defer", "else",
          "fallthrough", "false", "for", "func", "go", "goto", "if", "import", "interface",
          "iota", "map", "nil", "package", "range", "return", "select", "struct", "switch",
          "true", "type", "var",
        ],
        lineComments: ["//"],
        blockComments: [BlockCommentSyntax(open: "/*", close: "*/")],
        strings: [
          StringSyntax("`", escape: .noEscapes, spansLines: true),
          StringSyntax("\""),
          StringSyntax("'"),
        ])))
}
