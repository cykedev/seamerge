import MergeModel
import Testing

struct ResultDocumentTests {
  @Test func everyBlockHasOneSegmentAfterLoading() async throws {
    let buffer = try await ResultBuffer(MergeFixture.nineBlocks())

    #expect(buffer.document.segments.count == buffer.blocks.count)
    #expect(buffer.text == MergeFixture.nineBlocksText)
    #expect(
      buffer.segmentTexts == [
        "u0\n", "A1\n", "u2\n", "A3\nB3\n", "u4\n", "B5\n", "u6\n", "Y7\n", "u8\n",
      ])
    buffer.checkInvariants()
  }

  @Test func segmentsLieBackToBack() async throws {
    let buffer = try await ResultBuffer(MergeFixture.nineBlocks())

    var next = 0
    for block in buffer.blocks {
      #expect(buffer.document.range(of: block).lowerBound == next)
      next = buffer.document.range(of: block).upperBound
    }
    #expect(next == buffer.text.utf16.count)
  }

  @Test func loadingTakesTheChangedSideAndOpensConflicts() async throws {
    let buffer = try await ResultBuffer(MergeFixture.nineBlocks())
    let segments = buffer.document.segments

    #expect(
      segments.map(\.state) == [
        .untouched, .auto, .untouched, .open, .untouched, .auto, .untouched, .open, .untouched,
      ])
    #expect(segments[1].sources == [.a])
    #expect(segments[5].sources == [.b])
    #expect(segments[3].sources.isEmpty)
    #expect(buffer.document.openConflictCount == 2)
  }

  @Test func loadingTakesBForUnchangedBlocksAndIdenticalChanges() async throws {
    let exact = try await ResultBuffer(MergeFixture.sameChange())
    #expect(
      exact.document.segments.map(\.sources) == [[.base, .a, .b], [.a, .b], [.base, .a, .b]])

    // Where the comparison ignores the whitespace in which the inputs differ, B's whitespace is
    // taken.
    let session = try await merge(
      base: "u0\nx1\n", a: "u0 \ny1\n", b: "u0\t\ny1\t\n", mode: .ignoreWhitespaceAmount)
    try #require(session.blocks.map(\.kind) == [.unchanged, .changedInBoth])
    let lenient = ResultBuffer(session)

    #expect(lenient.text == "u0\t\ny1\t\n")
    #expect(lenient.document.segments.map(\.sources) == [[.b], [.b]])
  }

  @Test func openConflictHoldsAThenBAsItsPreviewWithoutTheBase() async throws {
    let buffer = try await ResultBuffer(MergeFixture.nineBlocks())

    #expect(buffer.document.previewText(for: buffer.blocks[3]) == "A3\nB3\n")
    #expect(buffer.text(of: buffer.blocks[3]) == "A3\nB3\n")
    // A deleted the line, so the preview has only B's.
    #expect(buffer.text(of: buffer.blocks[7]) == "Y7\n")
  }

  @Test func previewEndsEveryPartWithALineEnding() async throws {
    let session = try await merge(base: "x", a: "a", b: "b")
    let buffer = ResultBuffer(session)

    #expect(buffer.text == "a\nb\n")
    buffer.checkInvariants()
  }

  @Test func blockKeepsAnEmptySegmentWhenItsTextIsDeleted() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())

    buffer.type("", replacing: 3..<6)

    #expect(buffer.document.segments.count == buffer.blocks.count)
    #expect(buffer.document.segment(for: buffer.blocks[1]).length == 0)
    #expect(buffer.document.segment(for: buffer.blocks[1]).state == .edited)
    buffer.checkInvariants()
  }

  @Test func mergeOfEmptyFilesHasNoSegments() async throws {
    let buffer = try await ResultBuffer(merge(base: "", a: "", b: ""))

    #expect(buffer.document.segments.isEmpty)
    #expect(buffer.text.isEmpty)
    #expect(buffer.document.plan(for: TextReplacement(range: 0..<0, text: "x")).isEmpty)
  }
}
