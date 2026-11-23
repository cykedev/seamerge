import Foundation
import MergeModel
import Testing
import TextBasics

struct MergeWorkTests {
  static let labels = ConflictLabels(a: "feature/login", base: "a1b2c3d", b: "main")

  /// The nine blocks of ``MergeFixture/nineBlocks()`` with B chosen in block 1, “hand” typed
  /// over the text from within block 4 to within block 6, and both conflicts open.
  static func handWorkInNineBlocks() async throws -> ResultBuffer {
    var buffer = ResultBuffer(try await MergeFixture.nineBlocks())
    buffer.perform(buffer.document.planChoosing([.b], in: buffer.blocks[1]))
    let start = buffer.document.range(of: buffer.blocks[4]).lowerBound + 1
    let end = buffer.document.range(of: buffer.blocks[6]).lowerBound + 1
    buffer.type("hand", replacing: start..<end)
    try #require(
      buffer.document.segments.map(\.state) == [
        .untouched, .chosen, .untouched, .open, .edited, .edited, .edited, .open, .untouched,
      ])
    return buffer
  }

  /// The JSON object of `work` as the encoder writes it.
  static func object(of work: MergeWork) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(work))
    return try #require(object as? [String: Any])
  }

  /// `work` with its JSON object changed by `change`, decoded again.
  static func decoding(
    _ work: MergeWork, changedBy change: (inout [String: Any]) throws -> Void
  ) throws -> MergeWork {
    var object = try object(of: work)
    try change(&object)
    return try JSONDecoder().decode(
      MergeWork.self, from: JSONSerialization.data(withJSONObject: object))
  }

  @Test func thereIsNoWorkWhileEveryBlockIsAsLoaded() async throws {
    var buffer = ResultBuffer(try await MergeFixture.nineBlocks())
    #expect(try buffer.capturedWork() == nil)

    buffer.perform(buffer.document.planChoosing([.a], in: buffer.blocks[3]))
    #expect(try buffer.capturedWork() != nil)
    buffer.perform(buffer.document.planResettingAll())

    #expect(try buffer.capturedWork() == nil)
  }

  @Test func workKeepsTheModeTheFormatAndTheTime() async throws {
    let buffer = try await Self.handWorkInNineBlocks()

    let work = try #require(try buffer.capturedWork(currentBlock: buffer.blocks[5]))

    #expect(work.key == MergeKey(buffer.document.session.inputs))
    #expect(work.mode == .exact)
    #expect(work.format.lineEnding == .crlf)
    #expect(work.format.encoding == .utf8)
    #expect(work.savedAt == Date(timeIntervalSinceReferenceDate: 812_345_678.25))
  }

  @Test func restoringIntoTheSameBlocksGivesTheResultAsItWasBeforeTheAbort() async throws {
    let before = try await Self.handWorkInNineBlocks()
    let work = try #require(try before.capturedWork(currentBlock: before.blocks[5]))

    var (after, restoration) = try ResultBuffer.restoring(
      work, into: try await MergeFixture.nineBlocks())

    #expect(restoration.restartedBlockCount == 0)
    #expect(restoration.currentBlock == after.blocks[5])
    #expect(after.text == before.text)
    #expect(after.document.segments == before.document.segments)
    #expect(
      after.document.exportText(of: after.text, labels: Self.labels)
        == before.document.exportText(of: before.text, labels: Self.labels))
    after.checkInvariants()
    #expect(after.undoStack.count == 1)
    after.undo()
    #expect(after.text == MergeFixture.nineBlocksText)
    #expect(!after.document.canResetAll)
  }

  @Test func restoredPreviewsShowTheNamesOfTheNewResult() async throws {
    var before = ResultBuffer(
      try await MergeFixture.nineBlocks(), removalNotes: [.a: "feature removed these lines"])
    before.perform(before.document.planChoosing([.b], in: before.blocks[3]))
    let work = try #require(try before.capturedWork())

    let (after, restoration) = try ResultBuffer.restoring(
      work, into: try await MergeFixture.nineBlocks(),
      removalNotes: [.a: "topic removed these lines"])

    #expect(restoration.restartedBlockCount == 0)
    #expect(after.text(of: after.blocks[7]) == "topic removed these lines\nY7\n")
    #expect(after.text(of: after.blocks[3]) == "B3\n")
    after.checkInvariants()
  }

  @Test func restoringIntoOtherBlocksMovesDecisionsToBlocksWithTheSameLines() async throws {
    let exact = try await merge(
      base: ModeSwitchTests.base, a: ModeSwitchTests.a, b: ModeSwitchTests.b)
    var before = ResultBuffer(exact)
    before.perform(before.document.planChoosing([.b], in: before.blocks[1]))
    before.perform(before.document.planChoosing([.a, .b], in: before.blocks[3]))
    before.type("hand ", at: before.document.range(of: before.blocks[5]).lowerBound)
    let lenient = try await exact.recomputed(
      options: ComparisonOptions(mode: .ignoreWhitespaceAmount))

    let work = try #require(try before.capturedWork(currentBlock: before.blocks[5]))
    let (after, restoration) = try ResultBuffer.restoring(work, into: lenient)

    #expect(restoration.restartedBlockCount == 1)
    #expect(restoration.currentBlock == lenient.blocks[5])
    #expect(
      after.segmentTexts == ["u0\n", "A1\n", "w2\nu3\n", "A4\nB4\n", "u5\n", "hand B6\n", "u7\n"])
    #expect(
      after.document.segments.map(\.state) == [
        .untouched, .auto, .untouched, .chosen, .untouched, .edited, .untouched,
      ])
    after.checkInvariants()
  }

  @Test func currentBlockWithoutABlockOfTheSameLinesIsNotRestored() async throws {
    let exact = try await merge(
      base: ModeSwitchTests.base, a: ModeSwitchTests.a, b: ModeSwitchTests.b)
    var before = ResultBuffer(exact)
    before.perform(before.document.planChoosing([.a, .b], in: before.blocks[3]))
    let lenient = try await exact.recomputed(
      options: ComparisonOptions(mode: .ignoreWhitespaceAmount))

    let work = try #require(try before.capturedWork(currentBlock: before.blocks[1]))
    let (_, restoration) = try ResultBuffer.restoring(work, into: lenient)

    #expect(restoration.restartedBlockCount == 0)
    #expect(restoration.currentBlock == nil)
  }

  @Test func fingerprintTellsBlocksApartAndStaysTheSame() async throws {
    let exact = try await merge(
      base: ModeSwitchTests.base, a: ModeSwitchTests.a, b: ModeSwitchTests.b)
    let again = try await exact.recomputed(options: ComparisonOptions(mode: .exact))
    let lenient = try await exact.recomputed(
      options: ComparisonOptions(mode: .ignoreWhitespaceAmount))
    var fingerprints: [String] = []
    for session in [exact, again, lenient] {
      var buffer = ResultBuffer(session)
      buffer.perform(buffer.document.planChoosing([.a, .b], in: buffer.blocks[3]))
      let work = try #require(try buffer.capturedWork())
      fingerprints.append(try #require(try Self.object(of: work)["blocks"] as? String))
    }

    #expect(fingerprints[0] == fingerprints[1])
    #expect(fingerprints[0] != fingerprints[2])
    // Computed outside the app from the kinds and byte ranges of the seven blocks, so that a
    // change of the fingerprint across versions, which would turn every exact restoration into a
    // move by lines, shows here.
    #expect(fingerprints[0] == "bfa6ff79d3c11b9a487b56ef737f8a5e03e4d2d3feb1cff6ef32ca2c959a63d8")
  }

  @Test func workIsWrittenWithNamesOfItsOwn() async throws {
    let buffer = try await Self.handWorkInNineBlocks()
    let work = try #require(try buffer.capturedWork(currentBlock: buffer.blocks[5]))

    let object = try Self.object(of: work)

    #expect(object["formatVersion"] as? Int == 1)
    #expect(object["key"] as? String == work.key.rawValue)
    #expect(object["mode"] as? String == "exact")
    #expect(object["encoding"] as? String == "utf8")
    #expect(object["byteOrderMark"] as? Bool == false)
    #expect(object["lineEnding"] as? String == "crlf")
    #expect(object["text"] as? String == "u0\nx1\nu2\nuhand6\nu8\n")
    let segments = try #require(object["segments"] as? [[String: Any]])
    #expect(segments.map { $0["length"] as? Int } == [3, 3, 3, nil, 5, 0, 2, nil, 3])
    #expect(segments[1]["state"] as? String == "chosen")
    #expect(segments[1]["sources"] as? [String] == ["base", "b"])
    #expect(segments[1]["bytes"] as? [[Int]] == [[3, 6], [3, 6], [3, 6]])
    #expect(segments[5]["state"] as? String == "edited")
    #expect(segments[3]["state"] == nil)
    let current = try #require(object["currentBlock"] as? [String: Any])
    #expect(current["index"] as? Int == 5)
  }

  @Test func workOfAnotherFormatVersionIsNotDecoded() async throws {
    let buffer = try await Self.handWorkInNineBlocks()
    let work = try #require(try buffer.capturedWork())

    #expect(throws: DecodingError.self) {
      try Self.decoding(work) { $0["formatVersion"] = 2 }
    }
  }

  @Test func damagedWorkIsNotDecoded() async throws {
    let buffer = try await Self.handWorkInNineBlocks()
    let work = try #require(try buffer.capturedWork())

    #expect(throws: DecodingError.self) {
      try Self.decoding(work) { $0["text"] = "too short" }
    }
    #expect(throws: DecodingError.self) {
      try Self.decoding(work) { $0["mode"] = "approximate" }
    }
    #expect(throws: DecodingError.self) {
      try Self.decoding(work) { $0["key"] = "notes" }
    }
    #expect(throws: DecodingError.self) {
      try Self.decoding(work) { object in
        var segments = try #require(object["segments"] as? [[String: Any]])
        segments[1]["bytes"] = [[6, 3], [3, 6], [3, 6]]
        object["segments"] = segments
      }
    }
    #expect(throws: DecodingError.self) {
      try Self.decoding(work) { object in
        var segments = try #require(object["segments"] as? [[String: Any]])
        segments[3]["state"] = "open"
        object["segments"] = segments
      }
    }
  }

  @Test func workIsNotRestoredIntoAResultThatChangedSinceLoading() async throws {
    let work = try #require(try await Self.handWorkInNineBlocks().capturedWork())
    var buffer = ResultBuffer(try await MergeFixture.nineBlocks())
    buffer.type("x", at: 0)

    #expect(buffer.document.planRestoring(work) == nil)
  }

  @Test func decisionForAnInputThatTakesNoPartStartsAsLoaded() async throws {
    var buffer = ResultBuffer(try await merge(base: nil, a: "x\na\n", b: "x\nb\n"))
    let conflict = try #require(buffer.blocks.first { $0.kind == .conflict })
    buffer.perform(buffer.document.planChoosing([.a], in: conflict))
    let work = try #require(try buffer.capturedWork())
    let damaged = try Self.decoding(work) { object in
      var segments = try #require(object["segments"] as? [[String: Any]])
      segments[conflict.id]["sources"] = ["base"]
      object["segments"] = segments
    }

    let (after, restoration) = try ResultBuffer.restoring(damaged, into: buffer.document.session)

    #expect(restoration.restartedBlockCount == 1)
    #expect(restoration.plan.isEmpty)
    #expect(after.text == ResultDocument(session: buffer.document.session).initialText)
  }
}
