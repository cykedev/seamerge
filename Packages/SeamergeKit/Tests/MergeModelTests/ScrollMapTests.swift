import MergeModel
import Testing

/// The scroll map of ``MergeFixture/nineBlocks()``, in which every block takes one row and one
/// line of the result, except for block 3, whose preview takes two lines.
struct ScrollMapTests {
  @Test func rowsAndResultLinesMapBlockByBlockAtTheSameFraction() async throws {
    let buffer = try await ResultBuffer(MergeFixture.nineBlocks())
    let map = ScrollMap(document: buffer.document, text: buffer.text)

    #expect(map.resultLine(atRow: 2.5) == 2.5)
    #expect(map.resultLine(atRow: 3.5) == 4)
    #expect(map.resultLine(atRow: 4.25) == 5.25)
    #expect(map.row(atResultLine: 4) == 3.5)
    #expect(map.row(atResultLine: 5.25) == 4.25)
  }

  @Test func blockWithoutLinesInTheResultIsPassedOver() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())
    buffer.perform(buffer.document.planChoosing([], in: buffer.blocks[5]))
    let map = ScrollMap(document: buffer.document, text: buffer.text)

    #expect(map.resultLine(atRow: 5.5) == 6)
    #expect(map.row(atResultLine: 6) == 6)
    #expect(map.row(atResultLine: 5.5) == 4.5)
  }

  @Test func positionsBeyondTheBlocksMapOneToOne() async throws {
    let buffer = try await ResultBuffer(MergeFixture.nineBlocks())
    let map = ScrollMap(document: buffer.document, text: buffer.text)

    #expect(map.resultLine(atRow: 9.5) == 10.5)
    #expect(map.row(atResultLine: 10.5) == 9.5)
    #expect(map.resultLine(atRow: -1) == -1)
  }

  @Test func lineEndingsCountAsTheTextSystemBreaksLines() async throws {
    let session = try await merge(
      base: "u\r\nx\r\nv\r\n", a: "u\r\na\u{2028}b\r\nv\r\n", b: "u\r\nx\r\nv\r\n")
    let buffer = ResultBuffer(session)
    let map = ScrollMap(document: buffer.document, text: buffer.text)

    // Block 1 has one row and two lines in the result.
    #expect(map.resultLine(atRow: 1.5) == 2)
    #expect(map.resultLine(atRow: 2) == 3)
  }
}
