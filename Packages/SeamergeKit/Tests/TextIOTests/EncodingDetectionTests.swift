import Foundation
import Testing
import TextIO

struct EncodingDetectionTests {
  @Test func utf8WithoutByteOrderMarkIsRecognized() throws {
    let bytes = try fileBytes("Grüße, 東京 😀\n", in: .utf8)

    let text = try #require(try LoadedFile(bytes: bytes).decodedText)

    #expect(text.encoding == .utf8)
    #expect(!text.hasByteOrderMark)
    #expect(text.text == "Grüße, 東京 😀\n")
    #expect(text.utf8 == bytes)
  }

  @Test(arguments: TextEncoding.unicodeEncodings)
  func byteOrderMarkDecidesTheEncodingAndIsDropped(encoding: TextEncoding) throws {
    let bytes = try fileBytes("Grüße, 東京 😀\r\n", in: encoding, byteOrderMark: true)

    let file = try LoadedFile(bytes: bytes)
    let text = try #require(file.decodedText)

    #expect(text.encoding == encoding)
    #expect(text.hasByteOrderMark)
    #expect(text.text == "Grüße, 東京 😀\r\n")
    #expect(text.utf8 == Data("Grüße, 東京 😀\r\n".utf8))
    #expect(file.bytes == bytes)
  }

  @Test func windows1252IsRecognized() throws {
    let bytes = try fileBytes("“Grüße” – 5 €\n", in: .windows1252)

    let text = try #require(try LoadedFile(bytes: bytes).decodedText)

    #expect(text.encoding == .windows1252)
    #expect(text.text == "“Grüße” – 5 €\n")
    #expect(text.utf8 == Data("“Grüße” – 5 €\n".utf8))
  }

  @Test func singleNonASCIIByteIsDecodedAsSingleByteText() throws {
    let text = try #require(try LoadedFile(bytes: Data([0xE4])).decodedText)

    #expect([TextEncoding.windows1252, .isoLatin1].contains(text.encoding))
    #expect(text.text == "ä")
  }

  @Test func byteUndefinedInWindows1252FallsBackToLatin1() throws {
    let text = try #require(try LoadedFile(bytes: Data([0x41, 0x81, 0x0A])).decodedText)

    #expect(text.encoding == .isoLatin1)
    #expect(text.text == "A\u{81}\n")
  }

  @Test func invalidUTF8InTheMiddleIsNotReadAsUTF8() throws {
    let prefix = try fileBytes(String(repeating: "Grüße\n", count: 2000), in: .utf8)
    let bytes = prefix + Data([0xFF]) + Data("tail\n".utf8)

    let text = try #require(try LoadedFile(bytes: bytes).decodedText)

    #expect(text.encoding != .utf8)
    #expect(text.text.hasSuffix("tail\n"))
  }

  @Test func truncatedSequenceAtTheEndIsNotUTF8() throws {
    let bytes = Data("price: ".utf8) + Data([0xE2, 0x82])

    let text = try #require(try LoadedFile(bytes: bytes).decodedText)

    #expect(text.encoding != .utf8)
    #expect(text.text.hasPrefix("price: "))
  }

  @Test func byteOrderMarkWithInvalidContentFallsThrough() throws {
    let text = try #require(try LoadedFile(bytes: Data([0xFF, 0xFE, 0x41])).decodedText)

    #expect([TextEncoding.windows1252, .isoLatin1].contains(text.encoding))
    #expect(!text.hasByteOrderMark)
    #expect(text.text == "ÿþA")
  }

  @Test func utf16TextStartingWithNULIsNotTakenForUTF32() throws {
    let bytes = Data([0xFF, 0xFE, 0x00, 0x00, 0x41, 0x00])

    let text = try #require(try LoadedFile(bytes: bytes).decodedText)

    #expect(text.encoding == .utf16LittleEndian)
    #expect(text.text == "\u{0}A")
  }

  @Test func emptyFileIsEmptyUTF8Text() throws {
    let text = try #require(try LoadedFile(bytes: Data()).decodedText)

    #expect(text.encoding == .utf8)
    #expect(!text.hasByteOrderMark)
    #expect(text.text.isEmpty)
    #expect(text.lineEndingStyle == nil)
    #expect(!text.isMissingFinalLineBreak)
  }

  @Test func byteOrderMarkAloneIsEmptyText() throws {
    let text = try #require(try LoadedFile(bytes: Data([0xEF, 0xBB, 0xBF])).decodedText)

    #expect(text.encoding == .utf8)
    #expect(text.hasByteOrderMark)
    #expect(text.text.isEmpty)
    #expect(text.utf8.isEmpty)
  }

  @Test func nulByteMakesTheFileBinary() throws {
    let file = try LoadedFile(bytes: Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x0A]))

    #expect(file.isBinary)
    #expect(file.decodedText == nil)
  }

  @Test func nulInTheLastProbedByteMakesTheFileBinary() throws {
    let bytes = Data(repeating: 0x61, count: 8191) + Data([0x00])

    #expect(try LoadedFile(bytes: bytes).isBinary)
  }

  @Test func nulAfterTheProbedBytesKeepsTheFileText() throws {
    let bytes = Data(repeating: 0x61, count: 8192) + Data([0x00])

    let text = try #require(try LoadedFile(bytes: bytes).decodedText)

    #expect(text.encoding == .utf8)
    #expect(text.utf8 == bytes)
  }

  @Test func utf16WithoutByteOrderMarkNeedsAGivenEncoding() throws {
    let bytes = try fileBytes("Hello", in: .utf16LittleEndian)

    #expect(try LoadedFile(bytes: bytes).isBinary)
    let text = try #require(try LoadedFile(bytes: bytes, encoding: .utf16LittleEndian).decodedText)
    #expect(text.text == "Hello")
    #expect(!text.hasByteOrderMark)
  }

  @Test func givenEncodingOverridesDetection() throws {
    let bytes = try fileBytes("Grüße\n", in: .windows1252)

    let text = try #require(try LoadedFile(bytes: bytes, encoding: .macRoman).decodedText)

    #expect(text.encoding == .macRoman)
    #expect(text.text == String(data: bytes, encoding: .macOSRoman))
  }

  @Test func givenEncodingRejectsInvalidBytes() {
    #expect(throws: TextIOError.invalidBytes(.utf8)) {
      try LoadedFile(bytes: Data([0x41, 0xFF]), encoding: .utf8)
    }
    #expect(throws: TextIOError.invalidBytes(.windows1252)) {
      try LoadedFile(bytes: Data([0x81]), encoding: .windows1252)
    }
    #expect(throws: TextIOError.invalidBytes(.utf16BigEndian)) {
      try LoadedFile(bytes: Data([0x00, 0x41, 0x00]), encoding: .utf16BigEndian)
    }
    #expect(throws: TextIOError.invalidBytes(.utf16LittleEndian)) {
      try LoadedFile(bytes: Data([0x3D, 0xD8, 0x41, 0x00]), encoding: .utf16LittleEndian)
    }
  }

  @Test func givenEncodingReadsABinaryFileAsText() throws {
    let text = try #require(try LoadedFile(bytes: Data("a\0b".utf8), encoding: .utf8).decodedText)

    #expect(text.text == "a\0b")
  }

  @Test func givenEncodingDropsOnlyItsOwnByteOrderMark() throws {
    let marked = try fileBytes("A", in: .utf8, byteOrderMark: true)

    let utf8 = try #require(try LoadedFile(bytes: marked, encoding: .utf8).decodedText)
    let latin1 = try #require(try LoadedFile(bytes: marked, encoding: .isoLatin1).decodedText)

    #expect(utf8.hasByteOrderMark)
    #expect(utf8.text == "A")
    #expect(!latin1.hasByteOrderMark)
    #expect(latin1.text == "ï»¿A")
  }

  @Test func fileOnDiskIsReadWithItsBytes() throws {
    try withTemporaryDirectory { directory in
      let url = directory.appending(path: "file.txt")
      let bytes = try fileBytes("Grüße\r\n", in: .utf16BigEndian, byteOrderMark: true)
      try bytes.write(to: url)

      let file = try LoadedFile(contentsOf: url)

      #expect(file.bytes == bytes)
      #expect(file.decodedText?.encoding == .utf16BigEndian)
      #expect(file.decodedText?.text == "Grüße\r\n")
    }
  }
}
