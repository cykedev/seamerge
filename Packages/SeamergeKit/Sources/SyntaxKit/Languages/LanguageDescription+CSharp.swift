extension LanguageDescription {
  /// C#, with verbatim, raw and interpolated strings; its preprocessor directives are
  /// keywords.
  static let cSharp = LanguageDescription(
    name: "C#", fileExtensions: ["cs", "csx"],
    syntax: .code(
      CodeSyntax(
        keywords: [
          "abstract", "as", "async", "await", "base", "bool", "break", "byte", "case", "catch",
          "char", "checked", "class", "const", "continue", "decimal", "default", "delegate",
          "do", "double", "dynamic", "else", "enum", "event", "explicit", "extern", "false",
          "finally", "fixed", "float", "for", "foreach", "goto", "if", "implicit", "in", "init",
          "int", "interface", "internal", "is", "lock", "long", "nameof", "namespace", "new",
          "null", "object", "operator", "out", "override", "params", "partial", "private",
          "protected", "public", "readonly", "record", "ref", "required", "return", "sbyte",
          "sealed", "short", "sizeof", "stackalloc", "static", "string", "struct", "switch",
          "this", "throw", "true", "try", "typeof", "uint", "ulong", "unchecked", "unsafe",
          "ushort", "using", "var", "virtual", "void", "volatile", "when", "where", "while",
          "with", "yield",
        ],
        lineComments: ["//"],
        blockComments: [BlockCommentSyntax(open: "/*", close: "*/")],
        strings: [
          StringSyntax(
            "\"\"\"", prefixes: ["$"], escape: .noEscapes, spansLines: true,
            interpolations: [StringSyntax.Interpolation(open: "{", close: "}")]),
          StringSyntax("\"\"\"", escape: .noEscapes, spansLines: true),
          StringSyntax(
            "\"", prefixes: ["$@", "@$"], escape: .doubledDelimiter, spansLines: true,
            interpolations: [StringSyntax.Interpolation(open: "{", close: "}")]),
          StringSyntax("\"", prefixes: ["@"], escape: .doubledDelimiter, spansLines: true),
          StringSyntax(
            "\"", prefixes: ["$"],
            interpolations: [StringSyntax.Interpolation(open: "{", close: "}")]),
          StringSyntax("\""),
          StringSyntax("'"),
        ],
        keywordPrefixes: "#",
        variablePrefixes: "@")))
}
