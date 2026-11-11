import Foundation
import Testing

@testable import MergeEngine

@Suite("Two-way diff")
struct DiffTests {
  private func changedLines(_ diff: Diff) -> (a: [Int], b: [Int]) {
    (diff.changes.flatMap { Array($0.a.lines) }, diff.changes.flatMap { Array($0.b.lines) })
  }

  @Test(
    "Blocks cover both inputs and equal blocks are equal",
    arguments: Fixtures.diffCases.indices, Whitespace.allCases)
  func blocksAreValid(caseIndex: Int, whitespace: Whitespace) throws {
    let (pathA, pathB) = Fixtures.diffCases[caseIndex]
    let a = try Fixtures.data(pathA)
    let b = try Fixtures.data(pathB)
    expectValidDiff(try Diff(a, b, whitespace: whitespace), under: whitespace)
    expectValidDiff(try Diff(b, a, whitespace: whitespace), under: whitespace)
  }

  @Test("Exact diff reconstructs each input from the other", arguments: Fixtures.diffCases)
  func exactDiffReconstructsInputs(pathA: String, pathB: String) throws {
    let a = try Fixtures.data(pathA)
    let b = try Fixtures.data(pathB)
    let rebuilt = reconstructed(from: try Diff(a, b))
    #expect(rebuilt.a == a)
    #expect(rebuilt.b == b)
  }

  // a: "int x = 1;"  "  foo(a,b);"  "bar();"     "end" LF    "  lead"  "same"
  // b: "int  x =\t1;" "  foo(a, b);" "bar();   "  "end" CRLF  "\tlead"  "same"
  @Test(
    "Whitespace modes decide which lines differ",
    arguments: [
      (Whitespace.exact, [0, 1, 2, 3, 4]),
      (.ignoreLineEndings, [0, 1, 2, 4]),
      (.ignoreAmount, [1]),
      (.ignoreAll, []),
    ])
  func whitespaceModes(whitespace: Whitespace, changed: [Int]) throws {
    let input = try Fixtures.pair("diff-whitespace")
    let diff = try Diff(input.a, input.b, whitespace: whitespace)
    #expect(changedLines(diff).a == changed)
    #expect(changedLines(diff).b == changed)
    #expect(diff.isIdentical == changed.isEmpty)
  }

  @Test("Whitespace appearing between tokens is a change under -db")
  func appearingWhitespaceIsAChange() throws {
    #expect(try !Diff(Data("f(a,b)\n"), Data("f(a, b)\n"), whitespace: .ignoreAmount).isIdentical)
    #expect(try Diff(Data("f(a,b)\n"), Data("f(a, b)\n"), whitespace: .ignoreAll).isIdentical)
  }

  @Test("CRLF and LF differ only in exact mode")
  func crlfAgainstLF() throws {
    let input = try Fixtures.pair("diff-crlf")
    let exact = try Diff(input.a, input.b)
    #expect(exact.blocks.map(\.kind) == [.changed])
    #expect(exact.blocks.first?.a.lines == 0..<3)
    #expect(exact.blocks.first?.b.lines == 0..<3)

    for whitespace in [Whitespace.ignoreLineEndings, .ignoreAmount, .ignoreAll] {
      let diff = try Diff(input.a, input.b, whitespace: whitespace)
      #expect(diff.isIdentical, "\(whitespace)")
      #expect(diff.blocks.first?.b.byteRange == 0..<input.b.count, "\(whitespace)")
    }
  }

  @Test("A lone CR ends a line only when line endings are ignored")
  func loneCarriageReturn() throws {
    let a = Data("one\rtwo\n")
    let b = Data("one\ntwo\n")
    let exact = try Diff(a, b)
    #expect(exact.a.lineCount == 1)
    #expect(exact.b.lineCount == 2)

    let ignoring = try Diff(a, b, whitespace: .ignoreLineEndings)
    #expect(ignoring.a.lineCount == 2)
    #expect(ignoring.isIdentical)
  }

  @Test("A missing final newline is a change only in exact mode")
  func missingFinalNewline() throws {
    let input = try Fixtures.pair("diff-missing-final-newline")
    let exact = try Diff(input.a, input.b)
    #expect(changedLines(exact).a == [1])
    #expect(changedLines(exact).b == [1])
    for whitespace in [Whitespace.ignoreLineEndings, .ignoreAmount, .ignoreAll] {
      #expect(try Diff(input.a, input.b, whitespace: whitespace).isIdentical, "\(whitespace)")
    }
  }

  @Test("Under -dl a missing final newline equals LF or CR but not CRLF")
  func missingFinalNewlineAgainstCRLF() throws {
    let lastLine = Data("x\nlast")
    #expect(try Diff(lastLine, Data("x\nlast\n"), whitespace: .ignoreLineEndings).isIdentical)
    #expect(try Diff(lastLine, Data("x\nlast\r"), whitespace: .ignoreLineEndings).isIdentical)

    let crlf = try Diff(lastLine, Data("x\nlast\r\n"), whitespace: .ignoreLineEndings)
    #expect(crlf.changes.map(\.a.lines) == [1..<2])
    #expect(try Diff(lastLine, Data("x\nlast\r\n"), whitespace: .ignoreAmount).isIdentical)
    #expect(try Diff(lastLine, Data("x\nlast\r\n"), whitespace: .ignoreAll).isIdentical)
  }

  @Test("Empty inputs give no blocks, an insertion or a deletion")
  func emptyInputs() throws {
    let empty = try Fixtures.data("diff-empty/empty")
    let content = try Fixtures.data("diff-empty/content")

    let none = try Diff(empty, empty)
    #expect(none.blocks.isEmpty)
    #expect(none.a.lineCount == 0)

    let insertion = try Diff(empty, content)
    #expect(insertion.blocks.count == 1)
    #expect(insertion.blocks.first?.isInsertion == true)
    #expect(insertion.blocks.first?.b.byteRange == 0..<content.count)

    let deletion = try Diff(content, empty)
    #expect(deletion.blocks.count == 1)
    #expect(deletion.blocks.first?.isDeletion == true)
    #expect(deletion.blocks.first?.a.lines == 0..<2)
  }

  @Test("Bytes that are not UTF-8, and NUL bytes, are compared like any other")
  func nonUTF8Bytes() throws {
    let input = try Fixtures.pair("diff-nonutf8")
    #expect(String(data: input.a, encoding: .utf8) == nil)

    let diff = try Diff(input.a, input.b)
    #expect(diff.changes.map(\.a.lines) == [0..<1, 4..<4])
    #expect(diff.changes.map(\.b.lines) == [0..<1, 4..<5])
    #expect(diff.blocks[1].kind == .equal)
    #expect(diff.blocks[1].a.lines.contains(2), "the line with NUL bytes matches")
  }

  @Test("Separate changes become separate blocks")
  func separateChanges() throws {
    let input = try Fixtures.pair("diff-two-changes")
    let diff = try Diff(input.a, input.b)
    #expect(diff.changes.map(\.a.lines) == [1..<2, 4..<5])
    #expect(diff.changes.map(\.b.lines) == [1..<2, 4..<6])
  }
}
