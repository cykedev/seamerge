import Foundation
import MergeModel
import Testing

struct SessionTests {
  @Test func mergeWithABaseHasAllThreeRoles() async throws {
    let session = try await merge(base: "a\n", a: "b\n", b: "a\n")

    #expect(session.kind == .merge)
    #expect(session.inputs.roles == [.base, .a, .b])
    #expect(session.inputs.base?.label == "base")
    #expect(session.blocks.map(\.kind) == [.changedInA])
  }

  @Test func mergeWithoutABaseMergesAAndBAlone() async throws {
    let session = try await merge(base: nil, a: "same\nonly a\n", b: "same\n")

    #expect(session.inputs.roles == [.a, .b])
    #expect(session.inputs.base == nil)
    #expect(session.rowLayout.displayText(for: .base) == nil)
    #expect(session.blocks.allSatisfy { $0.base.isEmpty })
  }

  @Test func comparisonPutsTheOlderFileIntoA() async throws {
    let session = try await diff("old\n", "new\n", mode: .ignoreAllWhitespace)

    #expect(session.kind == .diff)
    #expect(session.inputs.roles == [.a, .b])
    #expect(session.inputs.a.text == "old\n")
    #expect(session.options.mode == .ignoreAllWhitespace)
    #expect(session.blocks.map(\.kind) == [.changed])
  }

  @Test func blocksAreNumberedByPosition() async throws {
    let session = try await merge(
      base: RowLayoutTests.base, a: RowLayoutTests.a, b: RowLayoutTests.b)

    #expect(session.blocks.map(\.id) == Array(session.blocks.indices))
  }

  @Test func blocksCoverEveryInputInOrder() async throws {
    let session = try await merge(
      base: RowLayoutTests.base, a: RowLayoutTests.a, b: RowLayoutTests.b)

    for role in session.inputs.roles {
      var next = 0
      for block in session.blocks {
        #expect(block.lines(in: role).lowerBound == next)
        next = block.lines(in: role).upperBound
      }
      #expect(next == session.rowLayout.lineCount(in: role))
    }
  }

  @Test func binaryFileIsRefused() async throws {
    let binary = SourceFile(bytes: Data([0x61, 0x00, 0x62]), label: "image")
    #expect(binary.isBinary)
    #expect(binary.text == nil)

    await #expect(throws: MergeModelError.binaryInput(.b)) {
      try await Session.merge(base: nil, a: SourceFile("a\n"), b: binary)
    }
    await #expect(throws: MergeModelError.binaryInput(.a)) {
      try await Session.diff(old: binary, new: SourceFile("a\n"))
    }
  }

  @Test func fileIsReadWithItsEncoding() throws {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "MergeModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: directory) } }
    let url = directory.appending(path: "latin1.txt")
    let bytes = Data([0x47, 0x72, 0xFC, 0xDF, 0x65, 0x0A])
    try bytes.write(to: url)

    let file = try SourceFile(contentsOf: url, label: "Latin-1")

    #expect(file.url == url)
    #expect(file.bytes == bytes)
    #expect(file.text == "Grüße\n")
  }

  @Test func textOfByteOrderMarkedFileIsComparedWithoutTheMark() async throws {
    let marked = SourceFile(bytes: Data([0xEF, 0xBB, 0xBF] + Array("a\nb\n".utf8)), label: "bom")

    let session = try await Session.diff(old: marked, new: SourceFile("a\nc\n"))

    #expect(try session.rowTexts(of: .a) == ["a", "b"])
    #expect(session.blocks.map(\.kind) == [.unchanged, .changed])
  }

  @Test func sessionIsCreatedFromTheMainActor() async throws {
    let session = try await Self.mergeOnMainActor()

    #expect(session.blocks.count == 1)
  }

  @MainActor
  private static func mergeOnMainActor() async throws -> Session {
    try await Session.merge(base: SourceFile("a\n"), a: SourceFile("a\n"), b: SourceFile("a\n"))
  }
}
