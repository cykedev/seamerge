import Foundation
import Testing

@testable import MergeEngine

/// Checks that a line buffer's offsets start at 0, grow strictly and end at
/// the end of its data.
func expectValidLineBuffer(
  _ buffer: LineBuffer, sourceLocation: SourceLocation = #_sourceLocation
) {
  #expect(buffer.offsets.first == 0, sourceLocation: sourceLocation)
  #expect(buffer.offsets.last == buffer.data.count, sourceLocation: sourceLocation)
  #expect(
    zip(buffer.offsets, buffer.offsets.dropFirst()).allSatisfy(<),
    "every line is non-empty", sourceLocation: sourceLocation)
}

/// Checks that the blocks of `diff` cover both inputs in order, alternate
/// between equal and changed, and that equal blocks are equal under `mode`.
func expectValidDiff(
  _ diff: Diff, under mode: Whitespace, sourceLocation: SourceLocation = #_sourceLocation
) {
  expectValidLineBuffer(diff.a, sourceLocation: sourceLocation)
  expectValidLineBuffer(diff.b, sourceLocation: sourceLocation)

  var nextA = 0
  var nextB = 0
  var previousKind: Diff.BlockKind?
  for block in diff.blocks {
    #expect(
      block.a.lines.lowerBound == nextA && block.b.lines.lowerBound == nextB,
      "blocks are contiguous", sourceLocation: sourceLocation)
    #expect(block.kind != previousKind, "kinds alternate", sourceLocation: sourceLocation)
    #expect(!(block.a.isEmpty && block.b.isEmpty), "no empty block", sourceLocation: sourceLocation)
    if block.kind == .equal {
      #expect(
        spansEqual(block.a, in: diff.a, block.b, in: diff.b, under: mode),
        "equal block is equal under \(mode)", sourceLocation: sourceLocation)
    }
    nextA = block.a.lines.upperBound
    nextB = block.b.lines.upperBound
    previousKind = block.kind
  }
  #expect(nextA == diff.a.lineCount && nextB == diff.b.lineCount, sourceLocation: sourceLocation)
}

/// Rebuilds B from A's equal blocks and B's changed blocks, and A the other
/// way round. Exact only for ``Whitespace/exact``, where equal blocks are
/// byte-identical.
func reconstructed(from diff: Diff) -> (a: Data, b: Data) {
  diff.blocks.reduce(into: (a: Data(), b: Data())) { result, block in
    let bytesA = diff.a.bytes(lines: block.a.lines)
    let bytesB = diff.b.bytes(lines: block.b.lines)
    result.a += block.kind == .equal ? bytesB : bytesA
    result.b += block.kind == .equal ? bytesA : bytesB
  }
}
