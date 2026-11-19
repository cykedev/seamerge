import Foundation
import Testing
import TextBasics
import TextIO

struct LargeFileTests {
  @Test func fiftyMegabyteFileRoundTripsByteForByte() throws {
    let line = "Line with Grüße, 東京 and 😀 to keep every width busy\r\n"
    let lineCount = 50 * 1024 * 1024 / line.utf8.count + 1
    let bytes = Data(String(repeating: line, count: lineCount).utf8)
    #expect(bytes.count >= 50 * 1024 * 1024)

    try withTemporaryDirectory { directory in
      let url = directory.appending(path: "large.txt")
      try bytes.write(to: url)

      let file = try LoadedFile(contentsOf: url)
      let text = try #require(file.decodedText)
      #expect(text.encoding == .utf8)
      #expect(text.lineEndingStyle == .uniform(.crlf))
      #expect(text.utf8.count == bytes.count)

      let writer = TextWriter(encoding: .utf8, writesByteOrderMark: false, lineEnding: .crlf)
      try writer.write(text.text, to: url)

      #expect(try Data(contentsOf: url) == bytes)
    }
  }
}
