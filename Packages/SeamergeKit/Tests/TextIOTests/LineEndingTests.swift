import Foundation
import Testing
import TextBasics
import TextIO

struct LineEndingTests {
  private func decoded(_ text: String, in encoding: TextEncoding = .utf8) throws -> DecodedText {
    try #require(
      try LoadedFile(bytes: fileBytes(text, in: encoding), encoding: encoding).decodedText)
  }

  @Test(arguments: LineEnding.allCases)
  func singleKindOfLineEndingIsUniform(lineEnding: LineEnding) throws {
    let text = try decoded("one\(lineEnding.string)two\(lineEnding.string)")

    #expect(text.lineEndingStyle == .uniform(lineEnding))
    #expect(text.lineEndingStyle?.predominantLineEnding == lineEnding)
    #expect(!text.isMissingFinalLineBreak)
  }

  @Test func mixedLineEndingsAreCountedPerKind() throws {
    let text = try decoded("a\r\nb\nc\r\nd\re")

    #expect(text.lineEndingStyle == .mixed(LineEndingCounts(lf: 1, crlf: 2, cr: 1)))
    #expect(text.lineEndingStyle?.predominantLineEnding == .crlf)
    #expect(text.text == "a\r\nb\nc\r\nd\re")
  }

  @Test func tiedLineEndingsPreferLineFeed() throws {
    let text = try decoded("a\r\nb\nc")

    #expect(text.lineEndingStyle?.predominantLineEnding == .lf)
  }

  @Test func carriageReturnBeforeCarriageReturnLineFeedCountsAlone() throws {
    let text = try decoded("a\r\r\nb")

    #expect(text.lineEndingStyle == .mixed(LineEndingCounts(crlf: 1, cr: 1)))
  }

  @Test func textWithoutLineBreakHasNoStyle() throws {
    let text = try decoded("single line")

    #expect(text.lineEndingStyle == nil)
    #expect(text.isMissingFinalLineBreak)
  }

  @Test func missingFinalLineBreakIsReported() throws {
    #expect(try decoded("a\nb").isMissingFinalLineBreak)
    #expect(try !decoded("a\nb\n").isMissingFinalLineBreak)
    #expect(try !decoded("a\nb\r").isMissingFinalLineBreak)
  }

  @Test func lineEndingsOfUTF16TextAreCountedAfterDecoding() throws {
    let text = try decoded("a\r\nb\r\n", in: .utf16BigEndian)

    #expect(text.lineEndingStyle == .uniform(.crlf))
  }
}
