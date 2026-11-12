import Foundation
import Testing

@testable import SyntaxKit

/// Inputs built to drive a lexer into a loop or into work that grows faster than the input.
@Suite(.timeLimit(.minutes(1)))
struct RobustnessTests {
  /// Lines of a given length that open constructs again and again without closing them, or
  /// nearly match a delimiter at every position.
  private static let pathologicalLines: [(name: String, line: @Sendable (Int) -> String)] = [
    ("open comments", { repeated("/*", toLength: $0) }),
    ("open interpolations", { repeated("\"\\(", toLength: $0) }),
    ("open templates", { repeated("`${", toLength: $0) }),
    (
      "interpolations past the nesting limit",
      { repeated("\"\\(", toLength: 60) + repeated("\\(", toLength: $0) }
    ),
    ("raw string hashes", { String(repeating: "#", count: $0) + "\"" }),
    ("raw string word", { "R\"" + String(repeating: "x", count: $0) + "(" }),
    ("here documents", { repeated("<<EOF ", toLength: $0) }),
    ("backtick runs", { backtickRuns(toLength: $0) }),
    ("open attributes", { repeated("<a b=\"", toLength: $0) }),
    ("open markup", { repeated("<!--<![CDATA[<script>", toLength: $0) }),
    ("quotes", { repeated("'", toLength: $0) }),
    ("keys", { repeated("a: ", toLength: $0) }),
    ("spaces", { String(repeating: " ", count: $0) + "x" }),
    ("words", { repeated("x ", toLength: $0) }),
    ("numbers", { repeated("0x1.e+", toLength: $0) }),
    ("backslashes", { String(repeating: "\\", count: $0) }),
  ]

  private static func repeated(_ pattern: String, toLength length: Int) -> String {
    String(repeating: pattern, count: length / pattern.count)
  }

  /// Runs of one, two, three and more backticks, each unmatched.
  private static func backtickRuns(toLength length: Int) -> String {
    var text = ""
    var runLength = 1
    while text.utf8.count < length {
      text += String(repeating: "`", count: runLength) + " "
      runLength += 1
    }
    return text
  }

  /// Lexing a line four times as long reads at most four and a half times as many bytes; work
  /// that grows with the square of the length would read sixteen times as many.
  ///
  /// The bytes read are counted rather than the time taken, so that the result does not depend
  /// on the load of the machine.
  @Test(arguments: LanguageSample.all.map(\.fileName))
  func pathologicalLinesTakeWorkInProportionToTheirLength(fileName: String) {
    let language = LanguageDescription(fileName: fileName)
    for (name, makeLine) in Self.pathologicalLines {
      let short = makeLine(4_000)
      let long = makeLine(16_000)

      let shortWork = bytesRead(lexingTwice: short, as: language)
      let longWork = bytesRead(lexingTwice: long, as: language)

      #expect(
        2 * longWork <= 9 * shortWork,
        "\(name): \(shortWork) bytes read for 4 000, \(longWork) for 16 000 characters")
      for line in [short, long] {
        let lexed = LexedText(language: language, lines: [line, line])
        #expect(tokensLieInside(lexed, length: line.utf16.count), "\(name)")
      }
    }
  }

  /// The number of bytes read to lex a line twice, the second time in whatever the first left
  /// open.
  private func bytesRead(lexingTwice line: String, as language: LanguageDescription) -> Int {
    let lexer = Lexer(language: language)
    var count = 0
    withUnsafeMutablePointer(to: &count) { readCount in
      let first = lexer.lex(line, from: .initial, readCount: readCount)
      _ = lexer.lex(line, from: first.endState, readCount: readCount)
    }
    return count
  }

  /// Whether every token is non-empty, follows the one before it and ends inside its line.
  private func tokensLieInside(_ lexed: LexedText, length: Int) -> Bool {
    (0..<lexed.lineCount).allSatisfy { line in
      var end = 0
      return lexed.tokens(inLine: line).allSatisfy { token in
        defer { end = token.range.upperBound }
        return !token.range.isEmpty && token.range.lowerBound >= end
          && token.range.upperBound <= length
      }
    }
  }

  @Test(arguments: LanguageSample.all.map(\.fileName))
  func manyLinesOfOpenConstructsRelexInTime(fileName: String) {
    let language = LanguageDescription(fileName: fileName)
    var lines = Array(repeating: "/* /* \"\\( ${ `", count: 20_000)
    var lexed = LexedText(language: language, lines: lines)

    lines[0] = "*/ */ \" ) } `"
    let relexed = lexed.replaceLines(in: 0..<1, withLineCount: 1) { lines[$0] }

    #expect(relexed.lowerBound == 0)
    #expect(lexed.lineCount == lines.count)
  }

  @Test func unknownFileIsPlainTextAndHasNoTokens() {
    let language = LanguageDescription(fileName: "notes.unknown", firstLine: "/* hello */")
    let lines = AnnotatedText.plainLines(of: LanguageSample.swift.annotated)

    let lexed = LexedText(language: language, lines: lines)

    #expect(language == .plainText)
    #expect((0..<lexed.lineCount).allSatisfy { lexed.tokens(inLine: $0).isEmpty })
  }

  @Test func rangesCountUTF16CodeUnits() {
    expectTokens(#"«k:let» s = «s:"😀é"» «c:// ü 😀»"#, fileName: "a.swift")
  }

  @Test func lineBreaksAreNotPartOfTokens() {
    let lexed = LexedText(
      language: LanguageDescription(fileName: "a.swift"), lines: ["// a\r\n", "\"b\n", "c\r"])

    #expect(lexed.tokens(inLine: 0).map(\.range) == [0..<4])
    #expect(lexed.tokens(inLine: 1).map(\.range) == [0..<2])
    #expect(lexed.tokens(inLine: 2).isEmpty)
  }

  @Test func bridgedStringsAndSubstringsLexLikeStrings() {
    let text = "let café = \"Grüße\" // 東京"
    let language = LanguageDescription(fileName: "a.swift")
    let bridged = String(NSString(string: text))
    let substring = ("x" + text).dropFirst()

    let expected = LexedText(language: language, lines: [text]).tokens(inLine: 0)

    #expect(LexedText(language: language, lines: [bridged]).tokens(inLine: 0) == expected)
    #expect(LexedText(language: language, lines: [substring]).tokens(inLine: 0) == expected)
  }
}
