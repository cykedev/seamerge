import Foundation
import MergeModel
import Testing

struct ChangeCopyTests {
  /// The bytes of `text` as UTF-8.
  static func bytes(_ text: String) -> Data {
    Data(text.utf8)
  }

  /// The comparison of two files given by their bytes.
  static func comparison(
    _ old: Data, _ new: Data, mode: ComparisonMode = .exact, ignoring rules: [IgnoreRule] = []
  ) async throws -> Session {
    try await Session.diff(
      old: SourceFile(bytes: old, label: "old"), new: SourceFile(bytes: new, label: "new"),
      mode: mode, ignoring: rules)
  }

  /// The UTF-8 text of the target after `copy`.
  static func copiedText(_ session: Session, _ copy: ChangeCopy) throws -> String {
    String(decoding: try session.file(after: copy).bytes, as: UTF8.self)
  }

  /// The changed block at position `index` among the changed blocks of `session`.
  static func changed(_ index: Int, of session: Session) throws -> Block {
    let changed = session.blocks.filter { $0.kind == .changed }
    try #require(changed.indices.contains(index), "\(changed.count) changed blocks")
    return changed[index]
  }

  @Test func copyToRightRemovesTheBlockAndKeepsEveryOtherByteOfTheRight() async throws {
    let session = try await diff(
      "one\ntwo\nthree\nfour\nfive\n", "one\nTWO\nthree\nFOUR\nfive\n")

    let copy = ChangeCopy(block: try Self.changed(0, of: session), from: .a)
    let copied = try await session.copying(copy)

    #expect(copied.inputs.b.bytes == Self.bytes("one\ntwo\nthree\nFOUR\nfive\n"))
    #expect(copied.inputs.a.bytes == session.inputs.a.bytes)
    #expect(copied.blocks.map(\.kind) == [.unchanged, .changed, .unchanged])
    #expect(copied.blocks[1].b == 3..<4)
    #expect(session.blocks.filter { $0.kind == .changed }.count == 2)
  }

  @Test func copyToLeftChangesOnlyTheLeft() async throws {
    let session = try await diff("one\ntwo\nthree\n", "one\nTWO\nthree\n")

    let copied = try await session.copying(
      ChangeCopy(block: try Self.changed(0, of: session), from: .b))

    #expect(copied.inputs.a.bytes == Self.bytes("one\nTWO\nthree\n"))
    #expect(copied.inputs.b.bytes == session.inputs.b.bytes)
    #expect(copied.blocks.map(\.kind) == [.unchanged])
  }

  @Test func copiedFileKeepsTheLocationLabelAndEncodingOfTheTarget() async throws {
    let url = URL(filePath: "/tmp/target.txt")
    let session = try await Session.diff(
      old: SourceFile(bytes: Self.bytes("a\nb\n"), label: "Earlier Version"),
      new: SourceFile(bytes: Self.bytes("a\nc\n"), label: "main.swift", url: url))

    let file = try session.file(after: ChangeCopy(allChangesFrom: .a))

    #expect(file.url == url)
    #expect(file.label == "main.swift")
    #expect(file.encoding == .utf8)
    #expect(!file.hasByteOrderMark)
  }

  @Test func copyAllChangesToRightMakesTheRightByteEqualInExactMode() async throws {
    let old = "first\nkeep 1\nchanged\nkeep 2\nkeep 3\ninserted\nkeep 4\nlast\n"
    let new = "FIRST\nadded\nkeep 1\nCHANGED\nkeep 2\nremoved\nkeep 3\nkeep 4\n"
    let session = try await diff(old, new)
    try #require(session.blocks.filter { $0.kind == .changed }.count >= 4)

    let copied = try await session.copying(ChangeCopy(allChangesFrom: .a))

    #expect(copied.inputs.b.bytes == Self.bytes(old))
    #expect(copied.blocks.map(\.kind) == [.unchanged])
  }

  @Test func copyAllChangesToLeftMakesTheLeftByteEqualInExactMode() async throws {
    let old = "first\nkeep 1\nchanged\nkeep 2\n"
    let new = "added\nkeep 1\nCHANGED\nkeep 2\nlast"
    let session = try await diff(old, new)

    let copied = try await session.copying(ChangeCopy(allChangesFrom: .b))

    #expect(copied.inputs.a.bytes == Self.bytes(new))
    #expect(copied.blocks.map(\.kind) == [.unchanged])
  }

  @Test(arguments: [
    ("\r\n", "one\r\nTWO\r\nthree\r\nnew\r\n"),
    ("\r", "one\rTWO\rthree\rnew\r"),
  ])
  func copyAllChangesToATargetWithOtherLineEndingsDiffersOnlyInLineEndings(
    lineEnding: String, expected: String
  ) async throws {
    let old = "one\nTWO\nthree\nnew\n"
    let new = ["one", "two", "three"].map { $0 + lineEnding }.joined()
    let session = try await diff(old, new)

    let copied = try session.file(after: ChangeCopy(allChangesFrom: .a))

    #expect(copied.bytes == Self.bytes(expected))
    #expect(copied.lineEndingStyle == session.inputs.b.lineEndingStyle)
  }

  @Test(arguments: ComparisonMode.allCases)
  func copiedLinesTakeTheLineEndingOfACRLFTarget(mode: ComparisonMode) async throws {
    let session = try await diff("a\nb\nc\nd\n", "a\r\nB\r\nX\r\nd\r\n", mode: mode)

    let text = try Self.copiedText(
      session, ChangeCopy(block: try Self.changed(0, of: session), from: .a))

    #expect(text == "a\r\nb\r\nc\r\nd\r\n")
  }

  @Test func copiedLinesTakeTheLineEndingOfACRTarget() async throws {
    let session = try await diff("a\r\nb\r\nc\r\n", "a\rB\rc\r", mode: .ignoreLineEndings)

    let text = try Self.copiedText(
      session, ChangeCopy(block: try Self.changed(0, of: session), from: .a))

    #expect(text == "a\rb\rc\r")
  }

  @Test func copiedLinesTakeTheMostFrequentLineEndingOfAMixedTarget() async throws {
    // The target ends two lines with CRLF and one with LF; the copied lines take CRLF, and the
    // line that ends with LF stays as it is.
    let session = try await diff(
      "a\nb\nc\nd\n", "a\r\nB\nc\r\nD\r\n", mode: .ignoreLineEndings)

    let text = try Self.copiedText(
      session, ChangeCopy(block: try Self.changed(1, of: session), from: .a))

    #expect(text == "a\r\nB\nc\r\nd\r\n")
  }

  @Test func targetWithoutLineBreaksKeepsTheLineEndingsOfTheCopiedLines() async throws {
    let session = try await diff("one\r\ntwo\r\n", "")

    let text = try Self.copiedText(session, ChangeCopy(allChangesFrom: .a))

    #expect(text == "one\r\ntwo\r\n")
  }

  @Test func sourceWithoutFinalLineBreakEndsTheTargetWithoutOne() async throws {
    let session = try await diff("a\nb", "a\nc\n")

    #expect(try Self.copiedText(session, ChangeCopy(allChangesFrom: .a)) == "a\nb")
    #expect(try Self.copiedText(session, ChangeCopy(allChangesFrom: .b)) == "a\nc\n")
  }

  @Test func targetWithoutFinalLineBreakTakesTheOneOfTheSource() async throws {
    let session = try await diff("a\nb\n", "a\nc")

    #expect(try Self.copiedText(session, ChangeCopy(allChangesFrom: .a)) == "a\nb\n")
    #expect(try Self.copiedText(session, ChangeCopy(allChangesFrom: .b)) == "a\nc")
  }

  @Test func linesAddedAfterALastLineWithoutLineBreakStartOnALineOfTheirOwn() async throws {
    let session = try await diff("a\nb\n", "a", mode: .ignoreLineEndings)
    try #require(session.blocks.map(\.kind) == [.unchanged, .changed])

    let copied = try await session.copying(ChangeCopy(allChangesFrom: .a))

    #expect(copied.inputs.b.bytes == Self.bytes("a\nb\n"))
    #expect(copied.blocks.map(\.kind) == [.unchanged])
  }

  @Test func lastLineWithoutLineBreakGetsOneWhereTextOfTheTargetFollows() async throws {
    // The rule makes the last line of the right a block of its own that the left lacks, so the
    // copied last line of the left no longer ends the file.
    let rule = IgnoreRule(name: "Comment", pattern: "^#.*")
    let session = try await diff("a\nb", "a\nc\r\n# end\r\n", ignoring: [rule])
    try #require(session.blocks.map(\.kind) == [.unchanged, .changed, .unchanged])

    let text = try Self.copiedText(session, ChangeCopy(allChangesFrom: .a))

    #expect(text == "a\nb\r\n# end\r\n")
  }

  @Test func insertionAtTheStartOfTheFile() async throws {
    let session = try await diff("new\na\nb\n", "a\nb\n")

    let copied = try await session.copying(
      ChangeCopy(block: try Self.changed(0, of: session), from: .a))

    #expect(copied.inputs.b.bytes == Self.bytes("new\na\nb\n"))
    #expect(copied.blocks.map(\.kind) == [.unchanged])
  }

  @Test func insertionAtTheEndOfTheFile() async throws {
    let session = try await diff("a\nb\nnew\n", "a\nb\n")

    let copied = try await session.copying(ChangeCopy(allChangesFrom: .a))

    #expect(copied.inputs.b.bytes == Self.bytes("a\nb\nnew\n"))
    #expect(copied.blocks.map(\.kind) == [.unchanged])
  }

  @Test func deletionRemovesTheLinesOfTheTarget() async throws {
    let session = try await diff("a\nb\n", "a\nx\ny\nb\n")
    let block = try Self.changed(0, of: session)
    try #require(block.a.isEmpty)

    let copied = try await session.copying(ChangeCopy(block: block, from: .a))

    #expect(copied.inputs.b.bytes == Self.bytes("a\nb\n"))
    #expect(copied.blocks.map(\.kind) == [.unchanged])
  }

  @Test func deletionAtTheStartAndAtTheEndOfTheFile() async throws {
    let session = try await diff("b\n", "a\nb\nc\n")

    let first = try await session.copying(
      ChangeCopy(block: try Self.changed(0, of: session), from: .a))
    let last = try await session.copying(
      ChangeCopy(block: try Self.changed(1, of: session), from: .a))

    #expect(first.inputs.b.bytes == Self.bytes("b\nc\n"))
    #expect(last.inputs.b.bytes == Self.bytes("a\nb\n"))
  }

  @Test func changeOfTheFirstAndTheLastLine() async throws {
    let session = try await diff("A\nb\nZ\n", "a\nb\nz\n")

    let first = try Self.copiedText(
      session, ChangeCopy(block: try Self.changed(0, of: session), from: .a))
    let last = try Self.copiedText(
      session, ChangeCopy(block: try Self.changed(1, of: session), from: .a))

    #expect(first == "A\nb\nz\n")
    #expect(last == "a\nb\nZ\n")
  }

  @Test func targetInUTF16WithByteOrderMarkStaysSo() async throws {
    let target =
      Data([0xFF, 0xFE])
      + Data("a\r\nb\r\nc\r\n".utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })
    let session = try await Self.comparison(Self.bytes("a\n\u{DF}\u{20AC}\u{1F600}\nc\n"), target)
    try #require(session.inputs.b.encoding == .utf16LittleEndian)

    let file = try session.file(after: ChangeCopy(allChangesFrom: .a))

    let expected = "a\r\n\u{DF}\u{20AC}\u{1F600}\r\nc\r\n".utf16.flatMap {
      [UInt8($0 & 0xFF), UInt8($0 >> 8)]
    }
    #expect(file.bytes == Data([0xFF, 0xFE] + expected))
    #expect(file.encoding == .utf16LittleEndian)
    #expect(file.hasByteOrderMark)
  }

  @Test func targetInWindows1252StaysSo() async throws {
    // Curly quotes exist in Windows-1252 alone, so the right is recognized as such.
    let target = try #require("\u{201C}caf\u{E9}\u{201D}\nold\n".data(using: .windowsCP1252))
    let session = try await Self.comparison(
      Self.bytes("\u{201C}caf\u{E9}\u{201D}\n5 \u{20AC}\n"), target)
    try #require(session.inputs.b.encoding == .windows1252)

    let file = try session.file(after: ChangeCopy(allChangesFrom: .a))

    #expect(file.bytes == "\u{201C}caf\u{E9}\u{201D}\n5 \u{20AC}\n".data(using: .windowsCP1252))
    #expect(file.encoding == .windows1252)
  }

  @Test func charactersTheTargetCannotRepresentAreReportedAndNothingIsCopied() async throws {
    let target = try #require("\u{201C}a\u{201D}\nold\n".data(using: .windowsCP1252))
    let session = try await Self.comparison(
      Self.bytes("\u{201C}a\u{201D}\n\u{2713} done\n"), target)

    #expect(throws: MergeModelError.unrepresentableText(.windows1252)) {
      try session.file(after: ChangeCopy(allChangesFrom: .a))
    }
    await #expect(throws: MergeModelError.unrepresentableText(.windows1252)) {
      try await session.copying(ChangeCopy(allChangesFrom: .a))
    }
    #expect(session.inputs.b.bytes == target)
  }

  @Test func ignoringWhitespaceChangesCopiesTheWhitespaceLinesOfTheBlockAlong() async throws {
    // Under Ignore Whitespace Changes, "  bar" and "bar" differ, since whitespace stands where
    // there was none, and belong to the block; "k" and "k  " are equal, a difference the mode
    // passes over.
    let session = try await diff(
      "k\na\nfoo\n  bar\ne\n", "k  \na\nFOO\nbar\nbaz\ne\n", mode: .ignoreWhitespaceAmount)
    try #require(session.blocks.map(\.kind) == [.unchanged, .changed, .unchanged])
    try #require(!IgnoredDifferences(in: session).lines(in: .b).isEmpty)

    let copied = try await session.copying(ChangeCopy(allChangesFrom: .a))

    #expect(copied.inputs.b.bytes == Self.bytes("k  \na\nfoo\n  bar\ne\n"))
    #expect(copied.blocks.map(\.kind) == [.unchanged])
    #expect(IgnoredDifferences(in: copied).lines(in: .b) == IndexSet(integer: 0))
  }

  @Test func ignoreRulesCopyTheRealTextOfTheSource() async throws {
    let rule = IgnoreRule(name: "Build", pattern: #"build \d+"#)
    let session = try await diff(
      "v1 build 2024\nx build 2024 A\nz\n", "v1 build 1999\nx build 1999 B\nz\n",
      ignoring: [rule])
    try #require(session.blocks.map(\.kind) == [.unchanged, .changed, .unchanged])

    let copied = try await session.copying(ChangeCopy(allChangesFrom: .a))

    #expect(copied.inputs.b.bytes == Self.bytes("v1 build 1999\nx build 2024 A\nz\n"))
    #expect(copied.blocks.map(\.kind) == [.unchanged])
    #expect(copied.ignoreRules == [rule])
  }

  @Test func copyKeepsTheComparisonMode() async throws {
    let session = try await diff("a\nb\n", "a \nc\n", mode: .ignoreWhitespaceAmount)

    let copied = try await session.copying(ChangeCopy(allChangesFrom: .a))

    #expect(copied.options.mode == .ignoreWhitespaceAmount)
    #expect(copied.inputs.b.bytes == Self.bytes("a \nb\n"))
  }

  @Test func oneEndOfAMoveIsCopiedAlone() async throws {
    let first = MovedLinesTests.first
    let second = MovedLinesTests.second
    let third = MovedLinesTests.third
    let session = try await diff(first + second + "x\n" + third, second + "y\n" + third + first)
    let move = try #require(session.moves.first)
    let destination = session.blocks[move.destination.block]

    let copied = try await session.copying(ChangeCopy(block: destination, from: .a))

    #expect(copied.inputs.b.bytes == Self.bytes(second + "y\n" + third))
    #expect(copied.moves.isEmpty)
    let source = try Self.changed(0, of: copied)
    #expect(source.a == 0..<4)
    #expect(source.b.isEmpty)
  }
}
