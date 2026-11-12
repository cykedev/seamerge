extension LanguageDescription {
  /// Kotlin, with nested block comments, raw strings and templates.
  static let kotlin = LanguageDescription(
    name: "Kotlin", fileExtensions: ["kt", "kts"],
    syntax: .code(
      CodeSyntax(
        keywords: [
          "abstract", "actual", "annotation", "as", "break", "by", "catch", "class",
          "companion", "const", "constructor", "continue", "crossinline", "data", "do", "else",
          "enum", "expect", "external", "false", "final", "finally", "for", "fun", "if",
          "import", "in", "infix", "init", "inline", "inner", "interface", "internal", "is",
          "lateinit", "noinline", "null", "object", "open", "operator", "out", "override",
          "package", "private", "protected", "public", "reified", "return", "sealed",
          "super", "suspend", "tailrec", "this", "throw", "true", "try", "typealias",
          "typeof", "val", "var", "vararg", "when", "where", "while",
        ],
        lineComments: ["//"],
        blockComments: [BlockCommentSyntax(open: "/*", close: "*/", nests: true)],
        strings: [
          StringSyntax(
            "\"\"\"", escape: .noEscapes, spansLines: true,
            interpolations: [StringSyntax.Interpolation(open: "${", close: "}")]),
          StringSyntax(
            "\"", interpolations: [StringSyntax.Interpolation(open: "${", close: "}")]),
          StringSyntax("'"),
        ])))
}
