import SyntaxKit
import Testing

/// Expects a text, lexed as the language of a file name, to give the tokens written into it.
func expectTokens(
  _ annotated: String, fileName: String, sourceLocation: SourceLocation = #_sourceLocation
) {
  let lines = AnnotatedText.plainLines(of: annotated)
  let lexed = LexedText(language: LanguageDescription(fileName: fileName), lines: lines)
  #expect(
    AnnotatedText.annotatedLines(lines, lexed: lexed) == AnnotatedText.lines(of: annotated),
    sourceLocation: sourceLocation)
}
