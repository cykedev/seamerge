import Foundation
import Testing
import TextIO

/// Loading a file and writing its text back unchanged reproduces the file byte for byte.
struct RoundTripTests {
  /// Writes `file` back in the form it was loaded in.
  private func rewritten(_ file: LoadedFile) throws -> Data {
    let text = try #require(file.decodedText)
    let writer = TextWriter(
      encoding: text.encoding,
      writesByteOrderMark: text.hasByteOrderMark,
      lineEnding: text.lineEndingStyle?.predominantLineEnding ?? .lf)
    return try writer.encode(text.text)
  }

  /// A file in one of the forms the round trip is tested with.
  private struct Sample {
    let bytes: Data
    let hasByteOrderMark: Bool
  }

  /// Every combination of byte order mark and final line break that `encoding` allows.
  private func samples(in encoding: TextEncoding, lineEnding: LineEnding) throws -> [Sample] {
    let lines = encoding.sampleLines.joined(separator: lineEnding.string)
    let byteOrderMarks = encoding.supportsByteOrderMark ? [false, true] : [false]
    return try byteOrderMarks.flatMap { byteOrderMark in
      try [lines, lines + "last line without line break"].map {
        Sample(
          bytes: try fileBytes($0, in: encoding, byteOrderMark: byteOrderMark),
          hasByteOrderMark: byteOrderMark)
      }
    }
  }

  @Test(arguments: TextEncoding.allCases, LineEnding.allCases)
  func givenEncodingRoundTripsByteForByte(encoding: TextEncoding, lineEnding: LineEnding) throws {
    for sample in try samples(in: encoding, lineEnding: lineEnding) {
      let file = try LoadedFile(bytes: sample.bytes, encoding: encoding)

      #expect(try rewritten(file) == sample.bytes)
    }
  }

  @Test(arguments: TextEncoding.allCases, LineEnding.allCases)
  func detectedEncodingRoundTripsByteForByte(encoding: TextEncoding, lineEnding: LineEnding)
    throws
  {
    for sample in try samples(in: encoding, lineEnding: lineEnding) {
      let file = try LoadedFile(bytes: sample.bytes)
      // Without a byte order mark, UTF-16 and UTF-32 text holds NUL bytes and reads as binary.
      if encoding != .utf8, encoding.supportsByteOrderMark, !sample.hasByteOrderMark {
        #expect(file.isBinary)
        continue
      }

      #expect(try rewritten(file) == sample.bytes)
    }
  }

  @Test func invalidUTF8InTheMiddleRoundTripsByteForByte() throws {
    let prefix = try fileBytes(String(repeating: "Grüße\n", count: 2000), in: .utf8)
    let bytes = prefix + Data([0xFF]) + Data("tail\n".utf8)

    #expect(try rewritten(LoadedFile(bytes: bytes)) == bytes)
  }

  @Test(arguments: [Data(), Data([0xEF, 0xBB, 0xBF]), Data([0xFF, 0xFE]), Data("\n".utf8)])
  func degenerateFilesRoundTripByteForByte(bytes: Data) throws {
    #expect(try rewritten(LoadedFile(bytes: bytes)) == bytes)
  }

  @Test func everyByteRoundTripsThroughTheSingleByteEncodings() throws {
    // Without the carriage return the line endings are uniform, which a rewrite keeps.
    let allBytes = Data((0...255).map(UInt8.init).filter { $0 != 0x0D })
    for encoding in [TextEncoding.isoLatin1, .macRoman] {
      let file = try LoadedFile(bytes: allBytes, encoding: encoding)

      #expect(try rewritten(file) == allBytes, "\(encoding)")
    }
  }
}
