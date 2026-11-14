import MergeModel
import Testing

/// The scroll map of ``MergeFixture/nineBlocks()``, in which every block takes one row and one
/// line of the result, except for block 3, whose preview takes two lines.
struct ScrollMapTests {
  @Test func rowsAndResultLinesMapBlockByBlockAtTheSameFraction() async throws {
    let buffer = try await ResultBuffer(MergeFixture.nineBlocks())
    let map = ScrollMap(document: buffer.document, text: buffer.text)

    #expect(map.targetPosition(at: 2.5) == 2.5)
    #expect(map.targetPosition(at: 3.5) == 4)
    #expect(map.targetPosition(at: 4.25) == 5.25)
    #expect(map.sourcePosition(at: 4) == 3.5)
    #expect(map.sourcePosition(at: 5.25) == 4.25)
  }

  @Test func blockWithoutLinesInTheResultIsPassedOver() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())
    buffer.perform(buffer.document.planChoosing([], in: buffer.blocks[5]))
    let map = ScrollMap(document: buffer.document, text: buffer.text)

    #expect(map.targetPosition(at: 5.5) == 6)
    #expect(map.sourcePosition(at: 6) == 6)
    #expect(map.sourcePosition(at: 5.5) == 4.5)
  }

  @Test func positionsBeyondTheBlocksMapOneToOne() async throws {
    let buffer = try await ResultBuffer(MergeFixture.nineBlocks())
    let map = ScrollMap(document: buffer.document, text: buffer.text)

    #expect(map.targetPosition(at: 9.5) == 10.5)
    #expect(map.sourcePosition(at: 10.5) == 9.5)
    #expect(map.targetPosition(at: -1) == -1)
  }

  @Test func lineEndingsCountAsTheTextSystemBreaksLines() async throws {
    let session = try await merge(
      base: "u\r\nx\r\nv\r\n", a: "u\r\na\u{2028}b\r\nv\r\n", b: "u\r\nx\r\nv\r\n")
    let buffer = ResultBuffer(session)
    let map = ScrollMap(document: buffer.document, text: buffer.text)

    // Block 1 has one row and two lines in the result.
    #expect(map.targetPosition(at: 1.5) == 2)
    #expect(map.targetPosition(at: 2) == 3)
  }
}

/// Maps between the lines of the two sides of a comparison, as panes without filler rows couple.
struct SideScrollMapTests {
  /// A comparison with a change, a removal and an insertion.
  ///
  /// Old: `u0`, `x`, `u1`, `u2`, `gone1`, `gone2`, `u3`; new: `u0`, `X1`, `X2`, `u1`, `u2`,
  /// `u3`, `new`. Blocks: unchanged 0..<1, changed (1 line, 2 lines), unchanged 2, removal
  /// (2 lines, none), unchanged 1, insertion (none, 1 line).
  private func comparison() async throws -> Session {
    try await diff(
      "u0\nx\nu1\nu2\ngone1\ngone2\nu3\n", "u0\nX1\nX2\nu1\nu2\nu3\nnew\n")
  }

  @Test func changedBlockMapsAtTheSameFractionInBothDirections() async throws {
    let map = ScrollMap(session: try await comparison(), from: .lines(.a), to: .lines(.b))

    #expect(map.targetPosition(at: 1) == 1)
    #expect(map.targetPosition(at: 1.5) == 2)
    #expect(map.sourcePosition(at: 2) == 1.5)
    #expect(map.sourcePosition(at: 3) == 2)
  }

  @Test func removedLinesMapToTheBoundaryWhereTheyAreMissing() async throws {
    let map = ScrollMap(session: try await comparison(), from: .lines(.a), to: .lines(.b))

    // Through the removed lines, the other side stands still at its boundary.
    #expect(map.targetPosition(at: 4) == 5)
    #expect(map.targetPosition(at: 4.5) == 5)
    #expect(map.targetPosition(at: 5.75) == 5)
    // From the side without the lines, the boundary passes the block over.
    #expect(map.sourcePosition(at: 5) == 6)
    #expect(map.sourcePosition(at: 4.5) == 3.5)
  }

  @Test func insertedLinesMapToTheBoundaryWhereTheyAreMissing() async throws {
    let map = ScrollMap(session: try await comparison(), from: .lines(.a), to: .lines(.b))

    #expect(map.sourcePosition(at: 6) == 7)
    #expect(map.sourcePosition(at: 6.5) == 7)
    #expect(map.targetPosition(at: 7) == 7)
  }

  @Test func positionsAtAndBeyondTheEndsOfTheFilesMapOneToOne() async throws {
    let map = ScrollMap(session: try await comparison(), from: .lines(.a), to: .lines(.b))

    #expect(map.targetPosition(at: 0) == 0)
    #expect(map.targetPosition(at: 0.5) == 0.5)
    #expect(map.targetPosition(at: -2) == -2)
    #expect(map.targetPosition(at: 7.5) == 7.5)
    #expect(map.sourcePosition(at: 8) == 8)
  }

  @Test func linesMapToTheGridAndBack() async throws {
    let session = try await comparison()
    let layout = session.rowLayout
    for role in [Role.a, .b] {
      let map = ScrollMap(session: session, from: .lines(role), to: .grid)
      for line in 0..<layout.lineCount(in: role) {
        let row = layout.row(ofLine: line, in: role)
        let block = layout.block(atRow: row)
        // Within a block, a side's lines spread over all rows of the block.
        let lines = block.lines(in: role)
        let rows = layout.rows(of: block)
        let expected =
          Double(rows.lowerBound) + Double(line - lines.lowerBound) / Double(lines.count)
          * Double(rows.count)
        #expect(map.targetPosition(at: Double(line)) == expected)
        #expect(map.sourcePosition(at: expected) == Double(line))
      }
    }
  }

  @Test func mapOfASideWithoutLinesKeepsEveryPositionAtTheStart() async throws {
    let session = try await diff("", "a\nb\n")
    let map = ScrollMap(session: session, from: .lines(.b), to: .lines(.a))

    #expect(map.targetPosition(at: 0) == 0)
    #expect(map.targetPosition(at: 1.5) == 0)
    #expect(map.sourcePosition(at: 0) == 2)
  }
}
