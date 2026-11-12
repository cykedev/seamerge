extension LanguageDescription {
  /// SCSS, which adds line comments and variables to CSS.
  static let scss = LanguageDescription(
    name: "SCSS", fileExtensions: ["scss"],
    syntax: .code(
      CodeSyntax(
        keywords: [
          "and", "false", "inherit", "initial", "not", "null", "only", "or", "revert",
          "revert-layer", "true", "unset",
        ],
        lineComments: ["//"],
        blockComments: [BlockCommentSyntax(open: "/*", close: "*/")],
        strings: [StringSyntax("\""), StringSyntax("'")],
        keywordPrefixes: "@!",
        variablePrefixes: "$#",
        wordCharacters: "-")))
}
