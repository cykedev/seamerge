extension LanguageDescription {
  /// SQL; its keywords match regardless of case.
  static let sql = LanguageDescription(
    name: "SQL", fileExtensions: ["sql"],
    syntax: .code(
      CodeSyntax(
        keywords: [
          "add", "all", "alter", "and", "as", "asc", "begin", "between", "by", "case", "cast",
          "check", "column", "commit", "constraint", "create", "cross", "database", "declare",
          "default", "delete", "desc", "distinct", "drop", "else", "end", "except", "exists",
          "false", "foreign", "from", "full", "function", "grant", "group", "having", "if",
          "in", "index", "inner", "insert", "intersect", "into", "is", "join", "key", "left",
          "like", "limit", "natural", "not", "null", "offset", "on", "or", "order", "outer",
          "over", "partition", "primary", "procedure", "references", "rename", "replace",
          "return", "returning", "returns", "revoke", "right", "rollback", "schema", "select",
          "set", "table", "then", "to", "transaction", "trigger", "true", "union", "unique",
          "update", "using", "values", "view", "when", "where", "window", "with",
        ],
        keywordsIgnoreCase: true,
        lineComments: ["--"],
        blockComments: [BlockCommentSyntax(open: "/*", close: "*/")],
        strings: [
          StringSyntax("'", escape: .doubledDelimiter, spansLines: true),
          StringSyntax("\"", escape: .doubledDelimiter),
        ])))
}
