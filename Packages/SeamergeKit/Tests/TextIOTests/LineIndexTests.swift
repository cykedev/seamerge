import Foundation
import Testing
import TextBasics
import TextIO

struct LineIndexTests {
  /// The byte offsets where the lines of `text` start, split after each line feed, followed by
  /// the byte count.
  private func byteLineStarts(of text: String) -> LineStarts {
    let breaks = text.utf8.indices.filter { text.utf8[$0] == 0x0A }
      .map { text.utf8.distance(from: text.utf8.startIndex, to: $0) + 1 }
    let starts = [0] + breaks
    return LineStarts(starts.last == text.utf8.count ? starts : starts + [text.utf8.count])
  }

  private func index(of text: String) -> LineIndex {
    LineIndex(utf8: Data(text.utf8), byteLineStarts: byteLineStarts(of: text))
  }

  @Test func lineStartsCountUmlautsEmojiAndCJKInUTF16() {
    let index = index(of: "äö\n😀x\n你好\nend")

    #expect(index.lineCount == 4)
    #expect(index.utf16Range(ofLine: 0) == 0..<3)
    #expect(index.utf16Range(ofLine: 1) == 3..<7)
    #expect(index.utf16Range(ofLine: 2) == 7..<10)
    #expect(index.utf16Range(ofLine: 3) == 10..<13)
  }

  @Test func lineRangesMatchNSString() {
    let text = "Grüße\r\n👩‍💻 at 東京\n\n🇨🇭 ok\nlast"
    let index = index(of: text)
    let string = text as NSString

    var location = 0
    for line in 0..<index.lineCount {
      let expected = string.lineRange(for: NSRange(location: location, length: 0))
      #expect(index.utf16Range(ofLine: line) == expected.location..<NSMaxRange(expected))
      location = NSMaxRange(expected)
    }
    #expect(location == string.length)
  }

  @Test func offsetsWithinALineConvertBothWays() {
    let text = "a\nxäy😀z你\r\n"
    let index = index(of: text)
    let line = text.split(separator: "\n", omittingEmptySubsequences: false)[1]

    for position in line.unicodeScalars.indices + [line.unicodeScalars.endIndex] {
      let byteOffset = line.utf8.distance(from: line.utf8.startIndex, to: position)
      let utf16Offset = line.utf16.distance(from: line.utf16.startIndex, to: position)

      #expect(index.utf16Offset(ofByteOffset: byteOffset, inLine: 1) == utf16Offset)
      #expect(index.byteOffset(ofUTF16Offset: utf16Offset, inLine: 1) == byteOffset)
    }
  }

  @Test func utf16OffsetLiesInTheLineThatHoldsItAndTheEndInTheLast() {
    let index = index(of: "ä😀\nb\n")

    #expect((0..<4).map { index.line(containingUTF16Offset: $0) } == [0, 0, 0, 0])
    #expect(index.line(containingUTF16Offset: 4) == 1)
    #expect(index.line(containingUTF16Offset: 6) == 1)
  }

  @Test func emptyTextHasNoLines() {
    let index = LineIndex(utf8: Data(), byteLineStarts: LineStarts([0]))

    #expect(index.lineCount == 0)
  }

  @Test func bufferSliceIsIndexedFromItsStart() {
    let whole = Data("--äb\nc".utf8)
    let slice = whole.dropFirst(2)

    let index = LineIndex(utf8: slice, byteLineStarts: LineStarts([0, 4, 5]))

    #expect(index.utf16Range(ofLine: 0) == 0..<3)
    #expect(index.utf16Offset(ofByteOffset: 2, inLine: 0) == 1)
  }
}
