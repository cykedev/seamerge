import Foundation
import Testing

@testable import MergeEngine

@Suite("Three-way merge blocks")
struct MergeTests {
  private func merge(
    _ name: String, whitespace: Whitespace = .exact, strategy: MergeStrategy = .optimal
  ) throws -> Merge {
    let input = try Fixtures.triple(name)
    return try Merge(
      base: input.base, a: input.a, b: input.b, whitespace: whitespace, strategy: strategy)
  }

  private func kinds(_ merge: Merge) -> [Merge.BlockKind] { merge.blocks.map(\.kind) }

  @Test(
    "Blocks cover all inputs and match the text", arguments: Fixtures.mergeCases,
    Whitespace.allCases)
  func blocksAreValid(name: String, whitespace: Whitespace) throws {
    for strategy in MergeStrategy.allCases {
      expectValidMerge(
        try merge(name, whitespace: whitespace, strategy: strategy), under: whitespace)
    }
  }

  @Test("Separate changes on both sides merge cleanly")
  func separateChanges() throws {
    let result = try merge("merge-clean")
    #expect(
      kinds(result) == [
        .changedInB, .unchanged, .changedInA, .unchanged, .changedInB, .unchanged, .changedInA,
      ])
    #expect(result.result()?.data.text == "zero\none\nTWO\nthree\nfour\nFIVE\nsix\nseven\neight\n")
  }

  @Test("An identical change on both sides is not a conflict")
  func identicalChange() throws {
    let result = try merge("merge-same-change")
    #expect(kinds(result) == [.unchanged, .changedInBoth, .unchanged, .changedInB])
    let identical = result.blocks[1]
    #expect(identical.base.lines == 1..<2)
    #expect(identical.a.lines == 1..<2)
    #expect(identical.b.lines == 1..<2)
  }

  @Test("Changes to adjacent lines merge without conflict")
  func adjacentChanges() throws {
    let result = try merge("merge-adjacent")
    #expect(kinds(result) == [.unchanged, .changedInA, .changedInB, .unchanged])
    #expect(result.result()?.data.text == "l1\nL2-a\nL3-b\nl4\nl5\n")
  }

  @Test("Different changes to the same line conflict")
  func conflict() throws {
    let result = try merge("merge-conflict")
    #expect(kinds(result) == [.unchanged, .conflict, .unchanged])
    #expect(result.conflictCount == 1)
    let conflict = result.blocks[1]
    #expect([conflict.base.lines, conflict.a.lines, conflict.b.lines] == [1..<2, 1..<2, 1..<2])
  }

  @Test("An overlapping conflict is split along the lines A and B share")
  func splitConflict() throws {
    let result = try merge("merge-split-conflict")
    #expect(
      kinds(result) == [.unchanged, .conflict, .changedInBoth, .unchanged, .conflict, .unchanged])
    #expect(result.blocks[1].base.lines == 1..<3, "the first conflict takes both replaced lines")
    #expect(result.blocks[2].base.isEmpty)
    #expect(result.text(of: result.blocks[2], from: .a).text == "shared\n")
  }

  @Test("A deletion on one side and an edit elsewhere merge cleanly")
  func deletion() throws {
    let result = try merge("merge-delete")
    #expect(kinds(result) == [.unchanged, .changedInA, .unchanged, .changedInB])
    #expect(result.blocks[1].a.isEmpty)
    #expect(result.blocks[1].base.lines == 1..<3)
    #expect(result.result()?.data.text == "keep\nkeep2\nEND\n")
  }

  @Test("Deleting a line that the other side edits conflicts")
  func deletionAgainstEdit() throws {
    for strategy in MergeStrategy.allCases where strategy != .twoWay {
      let result = try merge("merge-delete-vs-edit", strategy: strategy)
      #expect(kinds(result) == [.unchanged, .conflict, .unchanged], "\(strategy)")
      #expect(result.blocks[1].a.isEmpty, "\(strategy)")
    }
  }

  @Test("Different insertions at the same place conflict")
  func insertionsAtSamePlace() throws {
    let result = try merge("merge-insert-same-place")
    #expect(kinds(result) == [.unchanged, .conflict, .unchanged])
    #expect(result.blocks[1].base.isEmpty)
  }

  @Test(
    "A whitespace-only edit is ignored by -db and -dw",
    arguments: [
      (Whitespace.exact, [Merge.BlockKind.unchanged, .conflict, .unchanged, .changedInB]),
      (.ignoreLineEndings, [.unchanged, .conflict, .unchanged, .changedInB]),
      (.ignoreAmount, [.unchanged, .changedInB]),
      (.ignoreAll, [.unchanged, .changedInB]),
    ])
  func whitespaceOnlyEdit(whitespace: Whitespace, expected: [Merge.BlockKind]) throws {
    #expect(kinds(try merge("merge-whitespace-edit", whitespace: whitespace)) == expected)
  }

  @Test(
    "A whitespace change against a text change of the same line",
    arguments: [
      (Whitespace.exact, true), (.ignoreLineEndings, true), (.ignoreAmount, false),
      (.ignoreAll, false),
    ])
  func whitespaceAgainstEdit(whitespace: Whitespace, conflicts: Bool) throws {
    let result = try merge("merge-whitespace-vs-edit", whitespace: whitespace)
    #expect(result.hasConflicts == conflicts)
    if !conflicts {
      #expect(result.result()?.data.text == "g(a, b);\nnext\n")
    }
  }

  @Test("Converting to CRLF is a change of every line unless line endings are ignored")
  func lineEndingConversion() throws {
    #expect(kinds(try merge("merge-crlf")) == [.conflict])
    let ignoring = try merge("merge-crlf", whitespace: .ignoreLineEndings)
    #expect(kinds(ignoring) == [.unchanged, .changedInB])
  }

  @Test("Adding a final newline changes the last line")
  func missingFinalNewline() throws {
    let exact = try merge("merge-missing-final-newline")
    #expect(kinds(exact) == [.changedInB, .changedInA])
    #expect(exact.result()?.data.text == "FIRST\nsecond\nthird\n")

    let ignoring = try merge("merge-missing-final-newline", whitespace: .ignoreLineEndings)
    #expect(kinds(ignoring) == [.changedInB, .unchanged, .changedInA])
  }

  @Test("Empty inputs")
  func emptyInputs() throws {
    #expect(try merge("merge-empty-all").blocks.isEmpty)
    #expect(kinds(try merge("merge-empty-base")) == [.changedInA])

    let bothAdd = try merge("merge-empty-both-add")
    #expect(kinds(bothAdd) == [.conflict])
    #expect(bothAdd.blocks[0].base.isEmpty)
  }

  @Test("Bytes that are not UTF-8 merge like any other")
  func nonUTF8Bytes() throws {
    let result = try merge("merge-nonutf8")
    #expect(kinds(result) == [.changedInA, .unchanged, .changedInB])
    // "café!" / "naïve" / 0xFE in Latin-1: A's first line, B's last line.
    let expected: [UInt8] = [
      0x63, 0x61, 0x66, 0xE9, 0x21, 0x0A, 0x6E, 0x61, 0xEF, 0x76, 0x65, 0x0A, 0xFE, 0x0A,
    ]
    #expect(result.result()?.data == Data(expected))
  }

  @Test("The two-way strategy merges against an empty base")
  func twoWayStrategy() throws {
    let result = try merge("merge-clean", strategy: .twoWay)
    #expect(result.base.data.isEmpty)
    #expect(result.blocks.allSatisfy { $0.base.isEmpty })
    #expect(result.hasConflicts)
  }
}
