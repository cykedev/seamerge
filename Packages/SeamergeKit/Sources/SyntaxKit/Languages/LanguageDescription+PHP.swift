extension LanguageDescription {
  /// PHP, with here documents; its keywords match regardless of case.
  static let php = LanguageDescription(
    name: "PHP", fileExtensions: ["php", "phtml"], interpreters: ["php"],
    syntax: .code(
      CodeSyntax(
        keywords: [
          "abstract", "and", "array", "as", "break", "callable", "case", "catch", "class",
          "clone", "const", "continue", "declare", "default", "do", "echo", "else", "elseif",
          "empty", "enddeclare", "endfor", "endforeach", "endif", "endswitch", "endwhile",
          "enum", "extends", "false", "final", "finally", "fn", "for", "foreach", "function",
          "global", "goto", "if", "implements", "include", "include_once", "instanceof",
          "insteadof", "interface", "isset", "list", "match", "namespace", "new", "null", "or",
          "parent", "print", "private", "protected", "public", "readonly", "require",
          "require_once", "return", "self", "static", "switch", "throw", "trait", "true",
          "try", "unset", "use", "var", "while", "xor", "yield",
        ],
        keywordsIgnoreCase: true,
        lineComments: ["//", "#"],
        blockComments: [BlockCommentSyntax(open: "/*", close: "*/")],
        strings: [
          StringSyntax("\"", spansLines: true),
          StringSyntax("'", spansLines: true),
        ],
        hereDocuments: HereDocumentSyntax(introducers: ["<<<"], allowsSpaceBeforeWord: true),
        variablePrefixes: "$")))
}
