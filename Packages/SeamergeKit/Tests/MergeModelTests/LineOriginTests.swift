import MergeModel
import Testing

struct LineOriginTests {
  @Test func linesOfASingleSourceHaveNoOriginOfTheirOwn() async throws {
    let buffer = try await ResultBuffer(MergeFixture.nineBlocks())

    #expect(buffer.document.lineOrigins(of: buffer.text).isEmpty)
  }

  @Test func eachLineOfABlockOfSeveralSourcesComesFromItsSource() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())
    let conflict = buffer.blocks[3]
    let start = buffer.document.range(of: conflict).lowerBound

    buffer.perform(buffer.document.planChoosing([.b, .a], in: conflict))

    #expect(buffer.text(of: conflict) == "B3\nA3\n")
    let origins = buffer.document.lineOrigins(of: buffer.text)
    #expect(origins.map(\.range) == [start..<start + 3, start + 3..<start + 6])
    #expect(origins.map(\.roles) == [[.b], [.a]])
  }

  @Test func conflictResolvedByHandKeepsTheLinesOfEachSide() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())
    let conflict = buffer.blocks[3]
    let start = buffer.document.range(of: conflict).lowerBound
    buffer.perform(buffer.document.planResolvingByHand(conflict).plan)

    buffer.type("new\n", at: start + 3)

    #expect(buffer.text(of: conflict) == "A3\nnew\nB3\n")
    let origins = buffer.document.lineOrigins(of: buffer.text)
    #expect(
      origins.map(\.range) == [start..<start + 3, start + 3..<start + 7, start + 7..<start + 10])
    #expect(origins.map(\.roles) == [[.a], [], [.b]])
  }

  @Test func onlyTheLineTypedInCountsAsHandwritten() async throws {
    let session = try await merge(
      base: "a\nb\nc\nd\nx\n", a: "a\nb\nc\nd\ny\n", b: "a\nb\nc\nd\nx\n")
    var buffer = ResultBuffer(session)
    // Line c of the large unchanged block.
    buffer.type("!", at: 5)

    #expect(buffer.text == "a\nb\nc!\nd\ny\n")
    #expect(handwritten(in: buffer) == [4..<7])
  }

  @Test func newLinesAreHandwrittenAndTheirNeighboursAreNot() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())
    // At the end of A1, in the segment of block 1.
    buffer.type("\nnew\nlines", at: 5)

    #expect(buffer.text(of: buffer.blocks[1]) == "A1\nnew\nlines\n")
    #expect(handwritten(in: buffer) == [6..<16])
  }

  @Test func lineTypedBackWordForWordIsNoLongerHandwritten() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())
    buffer.type("x", at: 5)
    #expect(handwritten(in: buffer) == [3..<7])

    buffer.type("", replacing: 5..<6)

    #expect(buffer.document.segment(for: buffer.blocks[1]).state == .edited)
    #expect(handwritten(in: buffer).isEmpty)
  }

  @Test func conflictResolvedByHandComparesWithASideThenB() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())
    let conflict = buffer.blocks[3]
    buffer.perform(buffer.document.planResolvingByHand(conflict).plan)
    #expect(handwritten(in: buffer).isEmpty)

    buffer.type("+", at: 12)

    #expect(buffer.text(of: conflict) == "A3\n+B3\n")
    #expect(handwritten(in: buffer) == [12..<16])
  }

  @Test func everyLineOfABlockThatTakesNothingIsHandwritten() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())
    buffer.perform(buffer.document.planChoosing([], in: buffer.blocks[5]))
    let start = buffer.document.range(of: buffer.blocks[5]).lowerBound

    buffer.type("one\ntwo\n", at: start)

    #expect(handwritten(in: buffer) == [start..<start + 8])
  }

  @Test func linesEndAtEveryBreakOfTheTextSystem() async throws {
    let session = try await merge(base: "a\nx\n", a: "a\ny\n", b: "a\nx\n")
    var buffer = ResultBuffer(session)

    buffer.type("1\r\n2\r3\u{2028}", at: 0)

    #expect(buffer.text == "1\r\n2\r3\u{2028}a\ny\n")
    #expect(handwritten(in: buffer) == [0..<7])
  }

  /// The parts of the result text of `buffer` that were typed by hand, joined where they touch.
  private func handwritten(in buffer: ResultBuffer) -> [Range<Int>] {
    var ranges: [Range<Int>] = []
    for origin in buffer.document.lineOrigins(of: buffer.text) where origin.roles.isEmpty {
      if let last = ranges.last, last.upperBound == origin.range.lowerBound {
        ranges[ranges.count - 1] = last.lowerBound..<origin.range.upperBound
      } else {
        ranges.append(origin.range)
      }
    }
    return ranges
  }
}
