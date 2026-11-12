import SyntaxKit
import Testing

struct LanguageSampleTests {
  @Test(arguments: LanguageSample.all)
  func sampleFileLexesToItsExpectedTokens(sample: LanguageSample) {
    let lines = AnnotatedText.plainLines(of: sample.annotated)
    let language = LanguageDescription(fileName: sample.fileName, firstLine: lines[0])
    #expect(language.name == sample.language)

    let lexed = LexedText(language: language, lines: lines)

    let expected = AnnotatedText.lines(of: sample.annotated)
    let actual = AnnotatedText.annotatedLines(lines, lexed: lexed)
    #expect(actual.count == expected.count)
    for (index, (actualLine, expectedLine)) in zip(actual, expected).enumerated() {
      #expect(actualLine == expectedLine, "line \(index + 1)")
    }
  }

  @Test func everyLanguageOfTheFirstReleaseHasASample() {
    let languages = [
      "Swift", "Objective-C", "C", "C++", "Java", "Kotlin", "C#", "JavaScript", "TypeScript",
      "Python", "Ruby", "Go", "Rust", "PHP", "Shell", "SQL", "HTML", "XML", "CSS", "SCSS",
      "JSON", "YAML", "TOML", "Markdown",
    ]

    #expect(LanguageSample.all.map(\.language) == languages)
  }
}
