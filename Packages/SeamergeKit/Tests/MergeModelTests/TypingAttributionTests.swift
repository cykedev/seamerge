import MergeModel
import Testing

/// The attribution of text edits to segments.
///
/// In ``MergeFixture/nineBlocks()``, every segment is one line of three characters, except for
/// the preview of block 3, which has two.
struct TypingAttributionTests {
  @Test func editWithinASegmentChangesItsLengthAndMakesItEdited() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())
    let edit = TextReplacement(range: 4..<5, text: "BC")

    let plan = buffer.type(edit.text, replacing: edit.range)

    #expect(plan.replacements == [edit])
    #expect(buffer.text(of: buffer.blocks[1]) == "ABC\n")
    #expect(buffer.document.segments[1].state == .edited)
    #expect(buffer.document.segments[1].sources == [.a])
    #expect(buffer.document.segments.filter { $0.state == .edited }.count == 1)
    buffer.checkInvariants()
  }

  @Test func insertionAtABoundaryBelongsToTheSegmentStartingThere() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())

    buffer.type("z", at: 3)

    #expect(buffer.text(of: buffer.blocks[0]) == "u0\n")
    #expect(buffer.text(of: buffer.blocks[1]) == "zA1\n")
    #expect(buffer.document.segments[0].state == .untouched)
    #expect(buffer.document.segments[1].state == .edited)
  }

  @Test func insertionAtTheEndOfTheTextBelongsToTheLastSegmentWithText() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())

    buffer.type("z", at: buffer.text.utf16.count)

    #expect(buffer.text(of: buffer.blocks[8]) == "u8\nz")
    #expect(buffer.document.segments[8].state == .edited)
  }

  @Test func insertionAtTheEndOfTheTextPassesOverEmptySegments() async throws {
    let session = try await merge(base: "u0\nx1\n", a: "u0\n", b: "u0\nx1\n")
    try #require(session.blocks.map(\.kind) == [.unchanged, .changedInA])
    var buffer = ResultBuffer(session)

    buffer.type("z", at: 3)

    #expect(buffer.segmentTexts == ["u0\nz", ""])
    #expect(buffer.document.segments.map(\.state) == [.edited, .auto])
  }

  @Test func emptySegmentsNeverCatchTyping() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())
    buffer.perform(buffer.document.planChoosing([], in: buffer.blocks[5]))
    #expect(buffer.document.range(of: buffer.blocks[5]) == 18..<18)

    buffer.type("z", at: 18)

    #expect(buffer.text(of: buffer.blocks[5]) == "")
    #expect(buffer.document.segments[5].state == .chosen)
    #expect(buffer.text(of: buffer.blocks[6]) == "zu6\n")
    #expect(buffer.document.segments[6].state == .edited)
  }

  @Test func insertionBeforeAPreviewBelongsToTheSegmentEndingThere() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())
    let edit = TextReplacement(range: 9..<9, text: "z")

    let plan = buffer.type(edit.text, replacing: edit.range)

    #expect(plan.replacements == [edit])
    #expect(buffer.text(of: buffer.blocks[2]) == "u2\nz")
    #expect(buffer.document.segments[3].state == .open)
    buffer.checkInvariants()
  }

  @Test func insertionWithinAPreviewGoesToTheEndOfTheSegmentBeforeIt() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())

    let plan = buffer.type("z", at: 11)

    #expect(plan.replacements == [TextReplacement(range: 9..<9, text: "z")])
    #expect(buffer.segmentTexts[2...3] == ["u2\nz", "A3\nB3\n"])
    #expect(buffer.document.segments[3].state == .open)
  }

  @Test func selectingAllDeletingAndTypingPutsTheTextIntoTheFirstSegment() async throws {
    var buffer = try await ResultBuffer(MergeFixture.sameChange())

    buffer.type("", replacing: 0..<buffer.text.utf16.count)
    buffer.type("x", at: 0)

    #expect(buffer.segmentTexts == ["x", "", ""])
    #expect(buffer.document.segments.map(\.state) == [.edited, .edited, .edited])
    buffer.checkInvariants()
  }

  @Test func emptySegmentTakesTypingBeforeALeadingPreviewOnlyIfThereIsOne() async throws {
    let session = try await merge(base: "u0\nx1\nu2\n", a: "A1\nu2\n", b: "B1\nu2\n")
    try #require(session.blocks.map(\.kind) == [.conflict, .unchanged])
    var buffer = ResultBuffer(session)

    // No segment without a preview starts here or comes before, so the next one after takes it.
    let plan = buffer.type("z", at: 0)

    #expect(plan.replacements == [TextReplacement(range: 6..<6, text: "z")])
    #expect(buffer.segmentTexts == ["A1\nB1\n", "zu2\n"])
  }

  @Test func emptySegmentBetweenPreviewsTakesTyping() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())
    buffer.perform(buffer.document.planChoosing([], in: buffer.blocks[4]))
    buffer.perform(buffer.document.planChoosing([], in: buffer.blocks[5]))
    buffer.perform(buffer.document.planChoosing([], in: buffer.blocks[6]))
    #expect(buffer.text == "u0\nA1\nu2\nA3\nB3\nY7\nu8\n")

    // Between the previews of blocks 3 and 7 lie only the empty segments of blocks 4 to 6.
    buffer.type("z", at: 15)

    #expect(buffer.segmentTexts[3...7] == ["A3\nB3\n", "z", "", "", "Y7\n"])
    #expect(buffer.document.segments[4].state == .edited)
  }

  @Test func insertionWithNoSegmentToTakeItIsRefused() async throws {
    let session = try await merge(base: "x\n", a: "a\n", b: "b\n")
    try #require(session.blocks.map(\.kind) == [.conflict])
    let document = ResultDocument(session: session)

    // Before and after the preview, which is the only segment.
    #expect(document.plan(for: TextReplacement(range: 0..<0, text: "z")).isEmpty)
    #expect(document.plan(for: TextReplacement(range: 4..<4, text: "z")).isEmpty)
  }

  @Test func editAcrossSegmentsGivesTheTextToTheFirstAndEmptiesThoseBetween() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())
    let edit = TextReplacement(range: 16..<22, text: "x")

    // From the end of block 4 into the start of block 6.
    let plan = buffer.type(edit.text, replacing: edit.range)

    #expect(plan.replacements == [edit])
    #expect(buffer.segmentTexts[4...6] == ["ux", "", "6\n"])
    #expect(buffer.document.segments[4...6].map(\.state) == [.edited, .edited, .edited])
    buffer.checkInvariants()

    // Each of them can take a source again.
    buffer.perform(buffer.document.planChoosing([.b], in: buffer.blocks[5]))
    buffer.perform(buffer.document.planResetting(buffer.blocks[4]))
    buffer.perform(buffer.document.planResetting(buffer.blocks[6]))
    #expect(buffer.text == MergeFixture.nineBlocksText)
  }

  @Test func editAcrossAPreviewIsCarriedOutAroundIt() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())

    // From the end of block 2 across the preview of block 3 into the start of block 4.
    let plan = buffer.type("x", replacing: 7..<17)

    #expect(
      plan.replacements == [
        TextReplacement(range: 15..<17, text: ""), TextReplacement(range: 7..<9, text: "x"),
      ])
    #expect(buffer.segmentTexts[2...4] == ["ux", "A3\nB3\n", "\n"])
    #expect(buffer.document.segments[2...4].map(\.state) == [.edited, .open, .edited])
    buffer.checkInvariants()
  }

  @Test func editThatStartsInAPreviewGoesToTheSegmentAfterIt() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())

    buffer.type("x", replacing: 12..<16)

    #expect(buffer.segmentTexts[3...4] == ["A3\nB3\n", "x4\n"])
    #expect(buffer.document.segments[3...4].map(\.state) == [.open, .edited])
  }

  @Test func editWithinPreviewsAloneOnlyInsertsItsText() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())

    #expect(buffer.type("", replacing: 10..<14).isEmpty)
    buffer.type("x", replacing: 10..<14)

    #expect(buffer.segmentTexts[2...3] == ["u2\nx", "A3\nB3\n"])
  }

  @Test func typingNextToAnOpenConflictLeavesItOpen() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())

    buffer.type("before", at: 9)
    buffer.type("after", at: 21)

    #expect(buffer.document.segments[3].state == .open)
    #expect(buffer.text(of: buffer.blocks[3]) == "A3\nB3\n")
    #expect(buffer.text(of: buffer.blocks[4]) == "afteru4\n")
    #expect(buffer.document.openConflictCount == 2)
    buffer.checkInvariants()
  }

  @Test func editThatCoversASegmentExactlyStaysInIt() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())

    buffer.type("q", replacing: 3..<6)

    #expect(buffer.segmentTexts[0...2] == ["u0\n", "q", "u2\n"])
    #expect(buffer.document.segments[0...2].map(\.state) == [.untouched, .edited, .untouched])
  }

  @Test func boundaryMayLieWithinALineUntilASourceIsChosenAgain() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())

    buffer.type("", replacing: 2..<3)
    #expect(buffer.text.hasPrefix("u0A1\n"))
    #expect(buffer.document.range(of: buffer.blocks[1]) == 2..<5)

    buffer.perform(buffer.document.planToggling(.b, in: buffer.blocks[0]))
    #expect(buffer.text == MergeFixture.nineBlocksText)
    #expect(buffer.document.segments[0].state == .untouched)
  }
}
