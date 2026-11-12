extension LanguageDescription {
  /// The keywords of C, which Objective-C and C++ extend.
  static let cKeywords = [
    "alignas", "alignof", "auto", "bool", "break", "case", "char", "const", "constexpr",
    "continue", "default", "do", "double", "else", "enum", "extern", "false", "float", "for",
    "goto", "if", "inline", "int", "long", "nullptr", "register", "restrict", "return",
    "short", "signed", "sizeof", "static", "static_assert", "struct", "switch",
    "thread_local", "true", "typedef", "typeof", "union", "unsigned", "void", "volatile",
    "while", "_Alignas", "_Alignof", "_Atomic", "_Bool", "_Complex", "_Generic",
    "_Imaginary", "_Noreturn", "_Static_assert", "_Thread_local",
  ]

  /// The string and character literals of C, with the prefixes of wide and Unicode text.
  static let cStrings = [
    StringSyntax("\"", prefixes: ["", "L", "u", "U", "u8"]),
    StringSyntax("'", prefixes: ["", "L", "u", "U", "u8"]),
  ]

  /// C, whose preprocessor directives such as `#include` are keywords.
  static let c = LanguageDescription(
    name: "C", fileExtensions: ["c"],
    syntax: .code(
      CodeSyntax(
        keywords: cKeywords,
        lineComments: ["//"],
        blockComments: [BlockCommentSyntax(open: "/*", close: "*/")],
        strings: cStrings,
        keywordPrefixes: "#")))
}
