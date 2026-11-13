import Foundation
import Testing
import TextIO

struct TextWriterTests {
  @Test(arguments: LineEnding.allCases)
  func everyLineBreakBecomesTheChosenLineEnding(lineEnding: LineEnding) throws {
    let writer = TextWriter(encoding: .utf8, writesByteOrderMark: false, lineEnding: lineEnding)

    let bytes = try writer.encode("a\r\nb\nc\rd\n\re")

    let ending = lineEnding.string
    #expect(bytes == Data("a\(ending)b\(ending)c\(ending)d\(ending)\(ending)e".utf8))
  }

  @Test func finalLineBreakIsNeitherAddedNorRemoved() throws {
    let writer = TextWriter(encoding: .utf8, writesByteOrderMark: false, lineEnding: .crlf)

    #expect(try writer.encode("a\nb") == Data("a\r\nb".utf8))
    #expect(try writer.encode("a\nb\n") == Data("a\r\nb\r\n".utf8))
  }

  @Test(arguments: TextEncoding.unicodeEncodings)
  func byteOrderMarkPrecedesTheText(encoding: TextEncoding) throws {
    let writer = TextWriter(encoding: encoding, writesByteOrderMark: true, lineEnding: .lf)

    #expect(try writer.encode("😀\n") == fileBytes("😀\n", in: encoding, byteOrderMark: true))
    #expect(try writer.encode("") == Data(encoding.expectedByteOrderMark))
  }

  @Test func unrepresentableCharacterIsAnError() {
    let cases: [(TextEncoding, String)] = [
      (.windows1252, "Smile 😀"), (.isoLatin1, "5 €"), (.macRoman, "東京"),
    ]
    for (encoding, text) in cases {
      let writer = TextWriter(encoding: encoding, writesByteOrderMark: false, lineEnding: .lf)

      #expect(throws: TextIOError.unrepresentableText(encoding)) { try writer.encode(text) }
    }
  }

  @Test func writingKeepsTheExecutablePermission() throws {
    try withTemporaryDirectory { directory in
      let url = directory.appending(path: "script.sh")
      try Data("#!/bin/sh\necho old\n".utf8).write(to: url)
      try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
      let writer = TextWriter(encoding: .utf8, writesByteOrderMark: false, lineEnding: .lf)

      try writer.write("#!/bin/sh\necho new\n", to: url)

      let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
      #expect(attributes[.posixPermissions] as? Int == 0o755)
      #expect(try Data(contentsOf: url) == Data("#!/bin/sh\necho new\n".utf8))
    }
  }

  @Test func encodedBytesAreWrittenAsTheyAreAndKeepThePermissions() throws {
    try withTemporaryDirectory { directory in
      let url = directory.appending(path: "script.sh")
      try Data("old\n".utf8).write(to: url)
      try FileManager.default.setAttributes([.posixPermissions: 0o751], ofItemAtPath: url.path)
      let writer = TextWriter(encoding: .utf8, writesByteOrderMark: true, lineEnding: .crlf)
      let bytes = try writer.encode("new\n")

      try writer.write(bytes, to: url)

      let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
      #expect(attributes[.posixPermissions] as? Int == 0o751)
      #expect(try Data(contentsOf: url) == Data([0xEF, 0xBB, 0xBF]) + Data("new\r\n".utf8))
    }
  }

  @Test func writingKeepsExtendedAttributes() throws {
    try withTemporaryDirectory { directory in
      let url = directory.appending(path: "tagged.txt")
      try Data("old\n".utf8).write(to: url)
      let name = "app.eiden.seamerge.test"
      let value = Array("kept".utf8)
      let setResult = url.withUnsafeFileSystemRepresentation {
        setxattr($0, name, value, value.count, 0, 0)
      }
      try #require(setResult == 0)
      let writer = TextWriter(encoding: .utf8, writesByteOrderMark: false, lineEnding: .lf)

      try writer.write("new\n", to: url)

      var readBack = [UInt8](repeating: 0, count: 16)
      let length = url.withUnsafeFileSystemRepresentation {
        getxattr($0, name, &readBack, readBack.count, 0, 0)
      }
      #expect(length >= 0 && Array(readBack.prefix(length)) == value)
    }
  }

  @Test func writingLeavesNoOtherFileBehind() throws {
    try withTemporaryDirectory { directory in
      let url = directory.appending(path: "file.txt")
      try Data("old\n".utf8).write(to: url)
      let writer = TextWriter(encoding: .utf8, writesByteOrderMark: false, lineEnding: .lf)

      try writer.write("new\n", to: url)

      #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["file.txt"])
    }
  }

  @Test func writingCreatesAMissingFile() throws {
    try withTemporaryDirectory { directory in
      let url = directory.appending(path: "new.txt")
      let writer = TextWriter(encoding: .utf16BigEndian, writesByteOrderMark: true, lineEnding: .lf)

      try writer.write("Grüße\n", to: url)

      #expect(
        try Data(contentsOf: url) == fileBytes("Grüße\n", in: .utf16BigEndian, byteOrderMark: true))
    }
  }

  @Test func writingThroughASymbolicLinkReplacesItsTarget() throws {
    try withTemporaryDirectory { directory in
      let target = directory.appending(path: "target.txt")
      let link = directory.appending(path: "link.txt")
      try Data("old\n".utf8).write(to: target)
      try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
      let writer = TextWriter(encoding: .utf8, writesByteOrderMark: false, lineEnding: .lf)

      try writer.write("new\n", to: link)

      #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target.path)
      #expect(try Data(contentsOf: target) == Data("new\n".utf8))
    }
  }

  @Test func unrepresentableTextLeavesTheFileUntouched() throws {
    try withTemporaryDirectory { directory in
      let url = directory.appending(path: "file.txt")
      try Data("old\n".utf8).write(to: url)
      let writer = TextWriter(encoding: .isoLatin1, writesByteOrderMark: false, lineEnding: .lf)

      #expect(throws: TextIOError.unrepresentableText(.isoLatin1)) {
        try writer.write("😀\n", to: url)
      }
      #expect(try Data(contentsOf: url) == Data("old\n".utf8))
    }
  }
}
