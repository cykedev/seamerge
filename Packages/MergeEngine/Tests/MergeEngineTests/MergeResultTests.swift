import Foundation
import Testing

@testable import MergeEngine

@Suite("Merge result")
struct MergeResultTests {
  private let conflict: Merge

  init() throws {
    let input = try Fixtures.triple("merge-conflict")
    conflict = try Merge(base: input.base, a: input.a, b: input.b)
  }

  @Test("An unresolved conflict has no result")
  func unresolvedConflict() {
    #expect(conflict.result() == nil)
  }

  @Test(
    "Each source resolves a conflict",
    arguments: [
      (Merge.Source.a, "head\nvalue = 2\ntail\n"),
      (.b, "head\nvalue = 3\ntail\n"),
      (.base, "head\nvalue = 1\ntail\n"),
      (.aThenB, "head\nvalue = 2\nvalue = 3\ntail\n"),
      (.bThenA, "head\nvalue = 3\nvalue = 2\ntail\n"),
    ])
  func resolution(source: Merge.Source, expected: String) {
    #expect(conflict.result(resolutions: [1: source])?.data.text == expected)
  }

  @Test("Conflict markers in diff3 style include the base")
  func diff3Markers() {
    #expect(
      conflict.result(markingConflicts: .diff3).data.text == """
        head
        <<<<<<< A
        value = 2
        ||||||| BASE
        value = 1
        =======
        value = 3
        >>>>>>> B
        tail

        """)
  }

  @Test("Conflict markers in merge style carry the labels")
  func mergeMarkers() {
    let labels = Merge.ConflictLabels(a: "theirs", b: "mine")
    #expect(
      conflict.result(markingConflicts: .merge, labels: labels).data.text == """
        head
        <<<<<<< theirs
        value = 2
        =======
        value = 3
        >>>>>>> mine
        tail

        """)
  }

  @Test("A resolved conflict gets no markers")
  func resolvedConflictHasNoMarkers() {
    #expect(
      conflict.result(markingConflicts: .diff3, resolutions: [1: .b]).data.text
        == "head\nvalue = 3\ntail\n")
  }

  @Test("Marker lines start on a new line after a last line without newline")
  func markersAfterMissingFinalNewline() throws {
    let input = try Fixtures.triple("merge-missing-final-newline-conflict")
    let merge = try Merge(base: input.base, a: input.a, b: input.b)
    #expect(
      merge.result(markingConflicts: .diff3).data.text
        == "first\n<<<<<<< A\nlast-a\n||||||| BASE\nlast\n=======\nlast-b\n>>>>>>> B\n")
    #expect(merge.result(resolutions: [1: .a])?.data.text == "first\nlast-a")
    #expect(merge.result(resolutions: [1: .aThenB])?.data.text == "first\nlast-a\nlast-b")
  }

  @Test("Marker lines use the inputs' line ending")
  func markersUseCRLF() throws {
    let merge = try Merge(
      base: Data("x\r\nold\r\n"), a: Data("x\r\nnew-a\r\n"), b: Data("x\r\nnew-b\r\n"))
    #expect(
      merge.result(markingConflicts: .merge).data.text
        == "x\r\n<<<<<<< A\r\nnew-a\r\n=======\r\nnew-b\r\n>>>>>>> B\r\n")
  }

  @Test("Unchanged blocks take B's text by default")
  func unchangedBlocksUseB() throws {
    // A re-indents with a tab, B adds trailing spaces: equal under -db.
    let merge = try Merge(
      base: Data("if (x) {\n    call(1);\n}\n"), a: Data("if (x) {\n\tcall(1);\n}\n"),
      b: Data("if (x) {\n    call(1);  \n}\n"), whitespace: .ignoreAmount)
    #expect(merge.blocks.map(\.kind) == [.unchanged])
    #expect(merge.result()?.data.text == "if (x) {\n    call(1);  \n}\n")
    #expect(merge.result(resolutions: [0: .a])?.data.text == "if (x) {\n\tcall(1);\n}\n")
    #expect(merge.result(resolutions: [0: .base])?.data.text == "if (x) {\n    call(1);\n}\n")
  }

  @Test("Unchanged lines keep B's line endings when line endings are ignored")
  func ownLineEndingsAreKept() throws {
    // B converted to CRLF, A edited the last line.
    let merge = try Merge(
      base: Data("one\ntwo\nthree\n"), a: Data("one\ntwo\nTHREE\n"),
      b: Data("one\r\ntwo\r\nthree\r\n"), whitespace: .ignoreLineEndings)
    #expect(merge.blocks.map(\.kind) == [.unchanged, .changedInA])
    #expect(merge.result()?.data.text == "one\r\ntwo\r\nTHREE\n")
  }

  @Test("Identical changes take B's text by default")
  func identicalChangesUseB() throws {
    // A and B make the same edit, with different whitespace: equal under -db.
    let merge = try Merge(
      base: Data("x\n"), a: Data("y \n"), b: Data("y\t\n"), whitespace: .ignoreAmount)
    #expect(merge.blocks.map(\.kind) == [.changedInBoth])
    #expect(merge.result()?.data.text == "y\t\n")
    #expect(merge.result(resolutions: [0: .a])?.data.text == "y \n")
  }

  @Test("Block ranges hold each block's text, in order and without gaps")
  func blockRanges() throws {
    let input = try Fixtures.triple("merge-clean")
    let merge = try Merge(base: input.base, a: input.a, b: input.b)
    let output = try #require(merge.result())
    #expect(output.blockRanges.count == merge.blocks.count)
    #expect(output.blockRanges.first?.lowerBound == 0)
    #expect(output.blockRanges.last?.upperBound == output.data.count)
    #expect(
      zip(output.blockRanges, output.blockRanges.dropFirst()).allSatisfy {
        $0.upperBound == $1.lowerBound
      })
    for (block, range) in zip(merge.blocks, output.blockRanges) {
      let source = try #require(block.defaultSource)
      #expect(output.data.subdata(in: range) == merge.text(of: block, from: source))
    }
  }

  @Test("A conflict's range includes its markers")
  func conflictRangeIncludesMarkers() {
    let output = conflict.result(markingConflicts: .merge)
    #expect(
      output.blockRanges.map { output.data.subdata(in: $0).text } == [
        "head\n", "<<<<<<< A\nvalue = 2\n=======\nvalue = 3\n>>>>>>> B\n", "tail\n",
      ])
  }

  @Test("An inserted line ending belongs to the block whose last line it ends")
  func insertedLineEndingRange() throws {
    // Under -dl the unchanged block is B's "second" without a line ending,
    // followed by A's added line.
    let input = try Fixtures.triple("merge-missing-final-newline")
    let merge = try Merge(
      base: input.base, a: input.a, b: input.b, whitespace: .ignoreLineEndings)
    let output = try #require(merge.result())
    #expect(output.data.text == "FIRST\nsecond\nthird\n")
    #expect(
      output.blockRanges.map { output.data.subdata(in: $0).text } == [
        "FIRST\n", "second\n", "third\n",
      ])
  }

  @Test("A block resolved to no text has an empty range")
  func emptyBlockRange() throws {
    let input = try Fixtures.triple("merge-delete")
    let merge = try Merge(base: input.base, a: input.a, b: input.b)
    #expect(merge.blocks[1].kind == .changedInA && merge.blocks[1].a.isEmpty)
    let output = try #require(merge.result())
    #expect(output.blockRanges[1].isEmpty)
    #expect(output.blockRanges[1].lowerBound == output.blockRanges[0].upperBound)
  }

  @Test("Marker lines use CR in a file that ends its lines with CR only")
  func markersUseCR() throws {
    let merge = try Merge(base: Data("old\r"), a: Data("new-a\r"), b: Data("new-b\r"))
    #expect(
      merge.result(markingConflicts: .merge).data.text
        == "<<<<<<< A\rnew-a\r=======\rnew-b\r>>>>>>> B\r")
  }
}
