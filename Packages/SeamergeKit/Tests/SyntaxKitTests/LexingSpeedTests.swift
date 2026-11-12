import SyntaxKit
import Testing

struct LexingSpeedTests {
  /// Whether the tests run optimized, which a time limit needs to mean anything.
  ///
  /// Run them with `swift test -c release --filter LexingSpeedTests`.
  private static let isOptimized: Bool = {
    #if DEBUG
      return false
    #else
      return true
    #endif
  }()

  @Test(.enabled(if: isOptimized, "Timing needs an optimized build"))
  func hundredThousandLinesOfSwiftLexInUnder150Milliseconds() {
    let sample = AnnotatedText.plainLines(of: LanguageSample.swift.annotated)
    let lines = (0..<100_000).map { sample[$0 % sample.count] }
    let language = LanguageDescription(fileName: "Example.swift")
    let clock = ContinuousClock()

    var fastest = Duration.seconds(60)
    var lexed: LexedText?
    for _ in 0..<5 {
      let duration = clock.measure { lexed = LexedText(language: language, lines: lines) }
      fastest = min(fastest, duration)
    }

    #expect(lexed?.lineCount == lines.count)
    #expect(fastest < .milliseconds(150), "fastest of five runs: \(fastest)")
  }
}
