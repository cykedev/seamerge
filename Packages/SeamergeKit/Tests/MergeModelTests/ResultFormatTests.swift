import Foundation
import MergeModel
import Testing
import TextBasics

struct ResultFormatTests {
  private func session(base: Data, a: Data, b: Data) async throws -> Session {
    try await Session.merge(
      base: SourceFile(bytes: base, label: "base"), a: SourceFile(bytes: a, label: "a"),
      b: SourceFile(bytes: b, label: "b"))
  }

  private func utf16LittleEndianWithMark(_ text: String) -> Data {
    Data([0xFF, 0xFE]) + (text.data(using: .utf16LittleEndian) ?? Data())
  }

  @Test func resultIsWrittenLikeB() async throws {
    let b = utf16LittleEndianWithMark("one\r\ntwo\r\n")
    let format = ResultFormat(
      resultOf: try await session(base: Data("one\n".utf8), a: Data("one\n".utf8), b: b))

    #expect(format.encoding == .utf16LittleEndian)
    #expect(format.writesByteOrderMark)
    #expect(format.lineEnding == .crlf)
  }

  @Test func mixedLineEndingsOfBGiveTheMostFrequentOneAndATieGivesLF() async throws {
    let base = Data("x\n".utf8)
    let mostlyCRLF = try await session(base: base, a: base, b: Data("1\r\n2\r\n3\n".utf8))
    let tie = try await session(base: base, a: base, b: Data("1\r\n2\n".utf8))

    #expect(ResultFormat(resultOf: mostlyCRLF).lineEnding == .crlf)
    #expect(ResultFormat(resultOf: tie).lineEnding == .lf)
    #expect(mostlyCRLF.file(for: .b)?.predominantLineEnding == .crlf)
  }

  @Test func bWithoutLineBreakTakesTheLineEndingOfAThenOfTheBaseThenLF() async throws {
    let fromA = try await session(
      base: Data("x\n".utf8), a: Data("x\r\n".utf8), b: Data("x".utf8))
    let fromBase = try await session(base: Data("x\r".utf8), a: Data("y".utf8), b: Data("x".utf8))
    let none = try await session(base: Data("x".utf8), a: Data("y".utf8), b: Data("z".utf8))

    #expect(ResultFormat(resultOf: fromA).lineEnding == .crlf)
    #expect(ResultFormat(resultOf: fromBase).lineEnding == .cr)
    #expect(ResultFormat(resultOf: none).lineEnding == .lf)
  }

  @Test func anotherEncodingTakesItsByteOrderMarkExceptUTF8() {
    let utf8 = ResultFormat(encoding: .utf8, writesByteOrderMark: false, lineEnding: .lf)
    let utf8WithMark = ResultFormat(encoding: .utf8, writesByteOrderMark: true, lineEnding: .lf)

    #expect(utf8.with(encoding: .utf16BigEndian).writesByteOrderMark)
    #expect(!utf8.with(encoding: .windows1252).writesByteOrderMark)
    #expect(!utf8.with(encoding: .utf16BigEndian).with(encoding: .utf8).writesByteOrderMark)
    #expect(utf8WithMark.with(encoding: .utf8).writesByteOrderMark)
  }

  @Test func encodingWritesOneLineEndingAndKeepsAMissingFinalLineBreak() throws {
    let format = ResultFormat(encoding: .utf8, writesByteOrderMark: false, lineEnding: .crlf)

    #expect(try format.encode("a\nb\r\nc\rd") == Data("a\r\nb\r\nc\r\nd".utf8))
  }

  @Test func utf16IsWrittenWithItsByteOrderMark() throws {
    let format = ResultFormat(
      encoding: .utf16LittleEndian, writesByteOrderMark: true, lineEnding: .lf)

    #expect(try format.encode("hé\n") == utf16LittleEndianWithMark("hé\n"))
  }

  @Test func textTheEncodingCannotHoldIsRefusedBeforeAnythingIsWritten() throws {
    let folder = try temporaryFolder()
    defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: folder) } }
    let url = folder.appending(path: "result.txt")
    try Data("old\n".utf8).write(to: url)
    let format = ResultFormat(encoding: .isoLatin1, writesByteOrderMark: false, lineEnding: .lf)

    #expect(throws: MergeModelError.unrepresentableText(.isoLatin1)) {
      try format.write("📦\n", to: url)
    }
    #expect(try Data(contentsOf: url) == Data("old\n".utf8))
  }

  @Test func writingReplacesTheFileAndKeepsItsPermissions() throws {
    let folder = try temporaryFolder()
    defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: folder) } }
    let url = folder.appending(path: "script.sh")
    try Data("old\n".utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o751], ofItemAtPath: url.path)
    let format = ResultFormat(encoding: .utf8, writesByteOrderMark: false, lineEnding: .lf)

    try format.write("new\n", to: url)

    #expect(try Data(contentsOf: url) == Data("new\n".utf8))
    let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]
    #expect((permissions as? Int) == 0o751)
  }

  @Test func failureToWriteLeavesTheFileAsItWasAndNamesIt() throws {
    let folder = try temporaryFolder()
    defer {
      #expect(throws: Never.self) {
        try FileManager.default.setAttributes(
          [.posixPermissions: 0o755], ofItemAtPath: folder.path)
        try FileManager.default.removeItem(at: folder)
      }
    }
    let url = folder.appending(path: "result.txt")
    try Data("old\n".utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
    let format = ResultFormat(encoding: .utf8, writesByteOrderMark: false, lineEnding: .lf)

    let error = #expect(throws: MergeModelError.self) { try format.write("new\n", to: url) }

    guard case .writingFailed(let path, _) = error else {
      Issue.record("Expected writingFailed, got \(String(describing: error))")
      return
    }
    #expect(path == url.path(percentEncoded: false))
    #expect(try Data(contentsOf: url) == Data("old\n".utf8))
  }

  private func temporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appending(
      path: "ResultFormatTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }
}
