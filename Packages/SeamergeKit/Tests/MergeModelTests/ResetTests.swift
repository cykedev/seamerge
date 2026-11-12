import MergeModel
import Testing

struct ResetTests {
  @Test func resettingABlockRestoresItsTextAndSegmentAsLoadedInOneStep() async throws {
    let session = try await MergeFixture.nineBlocks()
    let loaded = ResultDocument(session: session).segments
    var buffer = ResultBuffer(session)
    let conflict = buffer.blocks[3]
    buffer.perform(buffer.document.planChoosing([.b, .a], in: conflict))
    buffer.type("hand", at: 10)
    let undoCount = buffer.undoStack.count

    buffer.perform(buffer.document.planResetting(conflict))

    #expect(buffer.text == MergeFixture.nineBlocksText)
    #expect(buffer.document.segments == loaded)
    #expect(buffer.undoStack.count == undoCount + 1)
    buffer.undo()
    #expect(buffer.text(of: conflict) == "Bhand3\nA3\n")
  }

  @Test func resettingConflictsReopensThemAndKeepsOtherDecisions() async throws {
    let session = try await MergeFixture.nineBlocks()
    let loaded = ResultDocument(session: session).segments
    var buffer = ResultBuffer(session)
    buffer.perform(buffer.document.planResolvingOpenConflicts(with: [.b]))
    buffer.type("!", at: 10)
    buffer.perform(buffer.document.planChoosing([.b], in: buffer.blocks[1]))

    buffer.perform(buffer.document.planResettingConflicts())

    #expect(buffer.document.openConflictCount == 2)
    #expect(buffer.text(of: buffer.blocks[1]) == "x1\n")
    #expect(buffer.document.segments[1].state == .chosen)
    buffer.perform(buffer.document.planResetting(buffer.blocks[1]))
    #expect(buffer.text == MergeFixture.nineBlocksText)
    #expect(buffer.document.segments == loaded)
  }

  @Test func resettingEverythingRestoresTheLoadedStateInOneStep() async throws {
    let session = try await MergeFixture.nineBlocks()
    let loaded = ResultDocument(session: session).segments
    var buffer = ResultBuffer(session)
    buffer.perform(buffer.document.planChoosing([.a, .b], in: buffer.blocks[3]))
    buffer.perform(buffer.document.planChoosing([], in: buffer.blocks[5]))
    buffer.type("x", replacing: 1..<8)
    buffer.moveCursor()
    buffer.type("y", at: buffer.text.utf16.count)
    let changed = buffer.text
    let undoCount = buffer.undoStack.count

    buffer.perform(buffer.document.planResettingAll())

    #expect(buffer.text == MergeFixture.nineBlocksText)
    #expect(buffer.document.segments == loaded)
    #expect(buffer.undoStack.count == undoCount + 1)
    buffer.undo()
    #expect(buffer.text == changed)
  }

  @Test func resetIsAvailableOnlyWhereSomethingDiffersFromLoading() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())
    #expect(!buffer.blocks.contains { buffer.document.canReset($0) })
    #expect(!buffer.document.canResetConflicts)
    #expect(!buffer.document.canResetAll)
    #expect(buffer.document.planResettingAll().isEmpty)

    buffer.perform(buffer.document.planChoosing([.base], in: buffer.blocks[5]))
    #expect(buffer.blocks.filter { buffer.document.canReset($0) }.map(\.id) == [5])
    #expect(!buffer.document.canResetConflicts)
    #expect(buffer.document.canResetAll)

    buffer.perform(buffer.document.planToggling(.a, in: buffer.blocks[7]))
    #expect(buffer.document.canResetConflicts)

    // Switching the toggle off again opens the conflict as it was loaded.
    buffer.perform(buffer.document.planToggling(.a, in: buffer.blocks[7]))
    #expect(!buffer.document.canResetConflicts)
  }

  @Test func editedBlockCountTellsInHowManyBlocksHandWorkWouldBeLost() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())
    #expect(buffer.document.editedBlockCount == 0)

    buffer.type("x", replacing: 1..<4)
    buffer.moveCursor()
    buffer.type("y", at: buffer.text.utf16.count)

    #expect(buffer.document.editedBlockCount == 3)
  }
}
