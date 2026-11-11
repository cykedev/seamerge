import Foundation
import Testing

@testable import MergeEngine

/// Ownership and lifetime at the C++ boundary, input limits, and concurrent
/// use.
@Suite("C++ boundary")
struct BoundaryTests {
  @Test("Inputs that are slices of larger buffers give the same result")
  func slicedInputs() throws {
    let input = try Fixtures.triple("merge-clean")
    let padding = Data("padding\n")
    let base = (padding + input.base).dropFirst(padding.count)
    let a = (padding + input.a).dropFirst(padding.count)
    let b = (padding + input.b).dropFirst(padding.count)
    #expect(base.startIndex != 0)

    let sliced = try Merge(base: base, a: a, b: b)
    let plain = try Merge(base: input.base, a: input.a, b: input.b)
    #expect(sliced.blocks == plain.blocks)
    #expect(sliced.result() == plain.result())
    #expect(sliced.a.data.startIndex == 0)
    #expect(sliced.a.line(0) == plain.a.line(0))

    let diff = try Diff(a, b)
    #expect(diff.blocks == (try Diff(input.a, input.b)).blocks)
  }

  @Test("Results stay valid after the inputs are released")
  func resultsOwnTheirData() throws {
    func makeMerge() throws -> Merge {
      var base = Data("one\ntwo\nthree\n")
      var a = Data("one\nTWO\nthree\n")
      var b = Data("one\ntwo\nTHREE\n")
      let merge = try Merge(base: base, a: a, b: b)
      base.resetBytes(in: 0..<base.count)
      a.resetBytes(in: 0..<a.count)
      b.resetBytes(in: 0..<b.count)
      return merge
    }
    #expect(try makeMerge().result()?.data.text == "one\nTWO\nTHREE\n")
  }

  @Test("Empty buffers without storage are accepted")
  func emptyBuffers() throws {
    #expect(try Diff(Data(), Data()).blocks.isEmpty)
    #expect(try Merge(base: Data(), a: Data(), b: Data()).blocks.isEmpty)
    #expect(try TokenDiff(Data(), Data("x")).changes.count == 1)
  }

  @Test("Inputs over Int32.max bytes are rejected before reaching the engine")
  func inputTooLarge() {
    // Zero-filled and never touched, so the pages are not materialized.
    let huge = Data(count: Int(Int32.max) + 1)
    #expect(throws: EngineError.inputTooLarge) { try Diff(huge, Data()) }
    #expect(throws: EngineError.inputTooLarge) { try Merge(base: Data(), a: huge, b: Data()) }
  }

  @Test("Concurrent merges and diffs give the same results as sequential ones")
  func concurrentUse() async throws {
    struct Outcome: Equatable {
      let merge: [Merge.Block]
      let diff: [Diff.Block]
      let tokens: [TokenDiff.Block]
    }
    func outcome(_ input: (base: Data, a: Data, b: Data)) throws -> Outcome {
      Outcome(
        merge: try Merge(base: input.base, a: input.a, b: input.b).blocks,
        diff: try Diff(input.a, input.b, whitespace: .ignoreAmount).blocks,
        tokens: try TokenDiff(input.a, input.b).blocks)
    }

    let inputs = try Fixtures.mergeCases.map { try Fixtures.triple($0) }
    let expected = try inputs.map(outcome)

    try await withThrowingTaskGroup(of: (Int, Outcome).self) { group in
      for _ in 0..<8 {
        for (index, input) in inputs.enumerated() {
          group.addTask { (index, try outcome(input)) }
        }
      }
      for try await (index, result) in group {
        #expect(result == expected[index], "\(Fixtures.mergeCases[index])")
      }
    }
  }

  @Test("Long lines and many lines")
  func largeInputs() throws {
    let longLine = Data(repeating: UInt8(ascii: "x"), count: 8 << 20)
    let diff = try Diff(longLine + Data("\nend\n"), longLine + Data("y\nend\n"))
    #expect(diff.blocks.map(\.kind) == [.changed, .equal])
    #expect(diff.blocks[0].b.byteRange == 0..<longLine.count + 2)

    let lines = (0..<200_000).map { "line \($0)\n" }
    let base = Data(lines.joined())
    var edited = lines
    edited[1_000] = "changed by A\n"
    let a = Data(edited.joined())
    edited = lines
    edited[150_000] = "changed by B\n"
    let b = Data(edited.joined())
    let merge = try Merge(base: base, a: a, b: b)
    #expect(
      merge.blocks.map(\.kind) == [.unchanged, .changedInA, .unchanged, .changedInB, .unchanged])
    #expect(merge.blocks[3].base.lines == 150_000..<150_001)
    let output = try #require(merge.result())
    #expect(output.data.subdata(in: output.blockRanges[1]).text == "changed by A\n")
    #expect(
      output.data
        == Data(
          (lines[..<1_000] + ["changed by A\n"] + lines[1_001..<150_000] + ["changed by B\n"]
            + lines[150_001...]).joined()))
  }
}
