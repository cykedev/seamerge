import Testing

/// A sample file of one language with its expected tokens, written as `AnnotatedText`.
struct LanguageSample: Sendable, CustomTestStringConvertible {
  /// The name of the language the file name should be recognized as.
  let language: String

  /// The name of the sample file, which decides its language.
  let fileName: String

  /// The text of the file with its expected tokens.
  let annotated: String

  var testDescription: String { language }

  /// One sample for each language.
  static let all: [LanguageSample] = [
    .swift, .objectiveC, .c, .cPlusPlus, .java, .kotlin, .cSharp, .javaScript, .typeScript,
    .python, .ruby, .go, .rust, .php, .shell, .sql, .html, .xml, .css, .scss, .json, .yaml,
    .toml, .markdown,
  ]
}
