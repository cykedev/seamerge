extension LanguageDescription {
  /// Python, with string prefixes, triple-quoted strings and interpolation in f-strings.
  static let python = LanguageDescription(
    name: "Python", fileExtensions: ["py", "pyi", "pyw"], interpreters: ["python"],
    syntax: .code(
      CodeSyntax(
        keywords: [
          "and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del",
          "elif", "else", "except", "False", "finally", "for", "from", "global", "if",
          "import", "in", "is", "lambda", "None", "nonlocal", "not", "or", "pass", "raise",
          "return", "True", "try", "while", "with", "yield",
        ],
        lineComments: ["#"],
        strings: [
          StringSyntax(
            "\"\"\"", prefixes: formattedPrefixes, spansLines: true,
            interpolations: [StringSyntax.Interpolation(open: "{", close: "}")]),
          StringSyntax(
            "'''", prefixes: formattedPrefixes, spansLines: true,
            interpolations: [StringSyntax.Interpolation(open: "{", close: "}")]),
          StringSyntax(
            "\"", prefixes: formattedPrefixes,
            interpolations: [StringSyntax.Interpolation(open: "{", close: "}")]),
          StringSyntax(
            "'", prefixes: formattedPrefixes,
            interpolations: [StringSyntax.Interpolation(open: "{", close: "}")]),
          StringSyntax("\"\"\"", prefixes: plainPrefixes, spansLines: true),
          StringSyntax("'''", prefixes: plainPrefixes, spansLines: true),
          StringSyntax("\"", prefixes: plainPrefixes),
          StringSyntax("'", prefixes: plainPrefixes),
        ])))

  /// The prefixes of Python’s f-strings and t-strings, which interpolate.
  private static let formattedPrefixes = ["f", "fr", "rf", "t", "tr", "rt"]

  /// The prefixes of Python’s other strings.
  private static let plainPrefixes = ["", "r", "u", "b", "br", "rb"]
}
