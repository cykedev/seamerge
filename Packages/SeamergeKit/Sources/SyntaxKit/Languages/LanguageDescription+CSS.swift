extension LanguageDescription {
  /// CSS, whose at-rules such as `@media` and `!important` are keywords; colors such as
  /// `#fff` stay plain like other identifiers.
  static let css = LanguageDescription(
    name: "CSS", fileExtensions: ["css"],
    syntax: .code(
      CodeSyntax(
        keywords: [
          "and", "inherit", "initial", "not", "only", "revert", "revert-layer", "unset",
        ],
        blockComments: [BlockCommentSyntax(open: "/*", close: "*/")],
        strings: [StringSyntax("\""), StringSyntax("'")],
        keywordPrefixes: "@!",
        variablePrefixes: "#",
        wordCharacters: "-")))
}
