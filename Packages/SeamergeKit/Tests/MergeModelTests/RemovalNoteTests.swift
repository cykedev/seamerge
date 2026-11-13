import MergeModel
import Testing

struct RemovalNoteTests {
  private static let notes: [Role: String] = [.a: "A removed these lines", .b: "B removed these"]

  @Test func previewShowsTheNoteOfASideThatRemovedTheLines() async throws {
    let buffer = try await ResultBuffer(MergeFixture.nineBlocks(), removalNotes: Self.notes)
    let conflict = buffer.blocks[7]

    #expect(buffer.text(of: conflict) == "A removed these lines\nY7\n")
    #expect(buffer.document.previewText(for: conflict) == "A removed these lines\nY7\n")
    #expect(buffer.document.previewLineCount(of: .a, in: conflict) == 1)
    #expect(buffer.document.previewLineCount(of: .b, in: conflict) == 1)
    buffer.checkInvariants()
  }

  @Test func sideWithLinesShowsNoNote() async throws {
    let buffer = try await ResultBuffer(MergeFixture.nineBlocks(), removalNotes: Self.notes)

    #expect(buffer.text(of: buffer.blocks[3]) == "A3\nB3\n")
  }

  @Test func withoutANoteTheSideShowsNothing() async throws {
    let buffer = try await ResultBuffer(MergeFixture.nineBlocks())

    #expect(buffer.text(of: buffer.blocks[7]) == "Y7\n")
    #expect(buffer.document.previewLineCount(of: .a, in: buffer.blocks[7]) == 0)
  }

  @Test func noteIsNeverWritten() async throws {
    let buffer = try await ResultBuffer(MergeFixture.nineBlocks(), removalNotes: Self.notes)
    let labels = ConflictLabels(a: "a", base: "base", b: "b")

    let exported = buffer.document.exportText(of: buffer.text, labels: labels)

    #expect(!exported.contains("removed"))
  }

  @Test func resolvingByHandDropsTheNote() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks(), removalNotes: Self.notes)
    let conflict = buffer.blocks[7]

    buffer.perform(buffer.document.planResolvingByHand(conflict).plan)

    #expect(buffer.text(of: conflict) == "Y7\n")
    #expect(buffer.document.segment(for: conflict).state == .edited)
    buffer.checkInvariants()
  }

  @Test func choosingTheRemovalEmptiesTheBlock() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks(), removalNotes: Self.notes)
    let conflict = buffer.blocks[7]

    buffer.perform(buffer.document.planChoosing([.a], in: conflict))

    #expect(buffer.text(of: conflict).isEmpty)
    buffer.perform(buffer.document.planResetting(conflict))
    #expect(buffer.text(of: conflict) == "A removed these lines\nY7\n")
  }

  @Test func switchingTheComparisonKeepsTheNotes() async throws {
    let session = try await MergeFixture.nineBlocks()
    let document = ResultDocument(session: session, removalNotes: Self.notes)
    let recomputed = try await session.recomputed(
      options: ComparisonOptions(mode: .ignoreAllWhitespace))

    let modeSwitch = document.planSwitching(to: recomputed, text: document.initialText)

    #expect(modeSwitch.plan.replacements.map(\.text) == [document.initialText])
  }
}
