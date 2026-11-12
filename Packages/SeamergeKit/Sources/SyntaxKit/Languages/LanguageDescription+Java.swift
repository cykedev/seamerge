extension LanguageDescription {
  /// Java, with text blocks.
  static let java = LanguageDescription(
    name: "Java", fileExtensions: ["java"],
    syntax: .code(
      CodeSyntax(
        keywords: [
          "abstract", "assert", "boolean", "break", "byte", "case", "catch", "char", "class",
          "const", "continue", "default", "do", "double", "else", "enum", "extends", "false",
          "final", "finally", "float", "for", "goto", "if", "implements", "import",
          "instanceof", "int", "interface", "long", "native", "new", "null", "package",
          "permits", "private", "protected", "public", "record", "return", "sealed", "short",
          "static", "strictfp", "super", "switch", "synchronized", "this", "throw", "throws",
          "transient", "true", "try", "var", "void", "volatile", "while", "yield",
        ],
        lineComments: ["//"],
        blockComments: [BlockCommentSyntax(open: "/*", close: "*/")],
        strings: [
          StringSyntax("\"\"\"", spansLines: true),
          StringSyntax("\""),
          StringSyntax("'"),
        ])))
}
