import SyntaxKit
import Testing

struct IncrementalLexingTests {
  private let swift = LanguageDescription(fileName: "a.swift")

  @Test func editInsideALineRelexesOnlyThatLine() {
    var lines = ["let a = 1", "let b = 2", "let c = 3"]
    var lexed = LexedText(language: swift, lines: lines)

    lines[1] = "let b = \"two\""
    let relexed = lexed.replaceLines(in: 1..<2, withLineCount: 1) { lines[$0] }

    #expect(relexed == 1..<2)
    #expect(lexed.tokens(inLine: 1) == LexedText(language: swift, lines: lines).tokens(inLine: 1))
  }

  @Test func openingABlockCommentRelexesUpToTheLineThatClosesIt() {
    var lines = ["let a = 1", "let b = 2", "end */", "let c = 3"]
    var lexed = LexedText(language: swift, lines: lines)

    lines[0] = "/* let a = 1"
    let relexed = lexed.replaceLines(in: 0..<1, withLineCount: 1) { lines[$0] }

    #expect(relexed == 0..<3)
    #expect(AnnotatedText.annotatedLines(lines, lexed: lexed)[1] == "«c:let b = 2»")
    #expect(lexed.tokens(inLine: 3) == LexedText(language: swift, lines: lines).tokens(inLine: 3))
  }

  @Test func insertingAndDeletingLinesShiftsTheLinesAfterThem() {
    var lines = ["let a = 1", "/* open", "still */", "let b = 2"]
    var lexed = LexedText(language: swift, lines: lines)

    lines.removeSubrange(1..<3)
    lexed.replaceLines(in: 1..<3, withLineCount: 0) { lines[$0] }
    #expect(lexed.lineCount == 2)

    lines.insert(contentsOf: ["\"\"\"", "text", "\"\"\""], at: 1)
    lexed.replaceLines(in: 1..<1, withLineCount: 3) { lines[$0] }
    #expect(lexed.lineCount == 5)

    let full = LexedText(language: swift, lines: lines)
    for line in 0..<lines.count {
      #expect(lexed.tokens(inLine: line) == full.tokens(inLine: line), "line \(line)")
    }
  }

  @Test(
    arguments: [
      ("a.swift", 1), ("a.swift", 2), ("a.cpp", 3), ("a.rb", 4), ("a.sh", 5), ("a.py", 6),
      ("a.html", 7), ("a.xml", 8), ("a.yaml", 9), ("a.toml", 10), ("a.md", 11), ("a.cs", 12),
    ] as [(String, UInt64)])
  func randomEditsLexLikeAFullRun(fileName: String, seed: UInt64) {
    let language = LanguageDescription(fileName: fileName)
    var generator = SplitMix64(seed: seed)
    var lines = (0..<40).map { _ in RandomCode.line(using: &generator) }
    var lexed = LexedText(language: language, lines: lines)

    for edit in 0..<300 {
      let start = Int.random(in: 0...lines.count, using: &generator)
      let end = Int.random(in: start...min(lines.count, start + 3), using: &generator)
      let replacement = (0..<Int.random(in: 0...3, using: &generator)).map { _ in
        RandomCode.line(using: &generator)
      }
      let before = (0..<lexed.lineCount).map { lexed.tokens(inLine: $0) }
      lines.replaceSubrange(start..<end, with: replacement)

      let relexed = lexed.replaceLines(in: start..<end, withLineCount: replacement.count) {
        lines[$0]
      }

      let full = LexedText(language: language, lines: lines)
      #expect(lexed.lineCount == lines.count)
      let after = (0..<lexed.lineCount).map { lexed.tokens(inLine: $0) }
      let expected = (0..<full.lineCount).map { full.tokens(inLine: $0) }
      #expect(after == expected, "seed \(seed), edit \(edit)")
      // Lines outside the relexed range kept their tokens.
      let shift = replacement.count - (end - start)
      #expect(Array(after[..<relexed.lowerBound]) == Array(before[..<relexed.lowerBound]))
      #expect(Array(after[relexed.upperBound...]) == Array(before[(relexed.upperBound - shift)...]))
      if after != expected { return }
    }
  }
}

/// Lines made of the fragments that open and close the constructs of every lexer family, so
/// that random edits often change what is open at the end of a line.
enum RandomCode {
  private static let fragments = [
    "/*", "*/", "\"", "\"\"\"", "'", "'''", "`", "```", "#\"", "\"#", "\\(", "${", "#{", "{",
    "}", "(", ")", "//", "#", "--", "<<EOF", "EOF", "<<-END", "END", "R\"x(", ")x\"", "=begin",
    "=end", "<!--", "-->", "<a b=", "<script>", "</script>", ">", "|", "- ", "key: ", " = ",
    "let", "x", " ", "1", "0x1F", "true", "\\", "@\"", "$\"", "# heading", "~~~",
  ]

  static func line(using generator: inout SplitMix64) -> String {
    (0..<Int.random(in: 0...6, using: &generator)).map { _ in
      fragments[Int.random(in: 0..<fragments.count, using: &generator)]
    }.joined()
  }
}
