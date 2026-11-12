import MergeModel
import Testing

struct UndoTests {
  @Test func undoRestoresTextAndSegmentsTogether() async throws {
    let session = try await MergeFixture.nineBlocks()
    let loaded = ResultDocument(session: session).segments
    var buffer = ResultBuffer(session)
    buffer.type("x", replacing: 7..<17)
    #expect(buffer.document.segments != loaded)

    buffer.undo()

    #expect(buffer.text == MergeFixture.nineBlocksText)
    #expect(buffer.document.segments == loaded)
  }

  @Test func continuedTypingIsOneStep() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())

    buffer.type("a", at: 4)
    buffer.type("b", at: 5)
    buffer.type("", replacing: 5..<6)
    buffer.type("c", at: 5)

    #expect(buffer.text(of: buffer.blocks[1]) == "Aac1\n")
    #expect(buffer.undoStack.count == 1)
    buffer.undo()
    #expect(buffer.text == MergeFixture.nineBlocksText)
  }

  @Test func aCommandOrAMoveOfTheCursorEndsTheTypingStep() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())

    buffer.type("a", at: 4)
    buffer.moveCursor()
    buffer.type("b", at: 5)
    buffer.perform(buffer.document.planToggling(.a, in: buffer.blocks[3]))
    buffer.type("c", at: 6)

    #expect(buffer.undoStack.count == 4)
    #expect(buffer.undoStack.map(\.isTyping) == [true, true, false, true])
  }

  @Test func onlyTypingStepsAreJoined() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())
    buffer.type("a", at: 4)
    buffer.perform(buffer.document.planToggling(.a, in: buffer.blocks[3]))
    buffer.perform(buffer.document.planToggling(.b, in: buffer.blocks[3]))
    let steps = buffer.undoStack

    #expect(steps[0].coalesced(with: steps[1]) == nil)
    #expect(steps[1].coalesced(with: steps[2]) == nil)
    #expect(steps[1].coalesced(with: steps[0]) == nil)
  }

  @Test func redoDoesTheUndoneStepAgain() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())
    buffer.perform(buffer.document.planChoosing([.b, .a], in: buffer.blocks[3]))
    buffer.type("x", replacing: 7..<17)
    let changed = buffer.text
    let segments = buffer.document.segments

    buffer.undo()
    buffer.undo()
    buffer.redo()
    buffer.redo()

    #expect(buffer.text == changed)
    #expect(buffer.document.segments == segments)
    #expect(buffer.redoStack.isEmpty)
  }

  @Test func undoTakesBackAnEditCarriedOutAroundAPreview() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())
    buffer.type("x", replacing: 7..<17)
    #expect(buffer.text.hasPrefix("u0\nA1\nuxA3\nB3\n\nB5\n"))

    buffer.undo()

    #expect(buffer.text == MergeFixture.nineBlocksText)
    buffer.checkInvariants()
  }
}
