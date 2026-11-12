extension LanguageDescription {
  /// Swift, with nested block comments, multi-line and raw strings, and interpolation.
  static let swift = LanguageDescription(
    name: "Swift", fileExtensions: ["swift"], interpreters: ["swift"],
    syntax: .code(
      CodeSyntax(
        keywords: [
          "actor", "any", "as", "associatedtype", "async", "await", "break", "case", "catch",
          "class", "continue", "convenience", "default", "defer", "deinit", "didSet", "do",
          "else", "enum", "extension", "fallthrough", "false", "fileprivate", "final", "for",
          "func", "guard", "if", "import", "in", "indirect", "init", "inout", "internal", "is",
          "isolated", "lazy", "let", "mutating", "nil", "nonisolated", "nonmutating",
          "operator", "override", "precedencegroup", "private", "protocol", "public",
          "repeat", "required", "rethrows", "return", "self", "Self", "some", "static",
          "struct", "subscript", "super", "switch", "throw", "throws", "true", "try",
          "typealias", "unowned", "var", "weak", "where", "while", "willSet",
        ],
        lineComments: ["//"],
        blockComments: [BlockCommentSyntax(open: "/*", close: "*/", nests: true)],
        strings: [
          StringSyntax(
            "\"\"\"", spansLines: true, rawDelimiter: .repeated("#"),
            interpolations: [StringSyntax.Interpolation(open: "\\(", close: ")")]),
          StringSyntax(
            "\"", rawDelimiter: .repeated("#"),
            interpolations: [StringSyntax.Interpolation(open: "\\(", close: ")")]),
        ],
        keywordPrefixes: "@#")))
}
