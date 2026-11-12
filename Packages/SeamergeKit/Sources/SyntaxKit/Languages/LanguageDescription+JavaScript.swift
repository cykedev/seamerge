extension LanguageDescription {
  /// The keywords of JavaScript, which TypeScript extends.
  static let javaScriptKeywords = [
    "async", "await", "break", "case", "catch", "class", "const", "continue", "debugger",
    "default", "delete", "do", "else", "export", "extends", "false", "finally", "for", "from",
    "function", "if", "import", "in", "instanceof", "let", "new", "null", "of", "return",
    "static", "super", "switch", "this", "throw", "true", "try", "typeof", "undefined", "var",
    "void", "while", "with", "yield",
  ]

  /// The syntax of JavaScript, with template literals; TypeScript differs only in its
  /// keywords.
  static func javaScriptSyntax(keywords: [String]) -> CodeSyntax {
    CodeSyntax(
      keywords: keywords,
      lineComments: ["//"],
      blockComments: [BlockCommentSyntax(open: "/*", close: "*/")],
      strings: [
        StringSyntax(
          "`", spansLines: true,
          interpolations: [StringSyntax.Interpolation(open: "${", close: "}")]),
        StringSyntax("\""),
        StringSyntax("'"),
      ],
      variablePrefixes: "$#",
      wordCharacters: "$")
  }

  /// JavaScript, including JSX.
  static let javaScript = LanguageDescription(
    name: "JavaScript", fileExtensions: ["js", "mjs", "cjs", "jsx"], interpreters: ["node"],
    syntax: .code(javaScriptSyntax(keywords: javaScriptKeywords)))
}
