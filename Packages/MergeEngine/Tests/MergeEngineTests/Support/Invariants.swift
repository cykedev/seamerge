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

/// Checks that the blocks of `merge` cover all three inputs in order and
/// that each block's kind matches the text under `mode`.
func expectValidMerge(
  _ merge: Merge, under mode: Whitespace, sourceLocation: SourceLocation = #_sourceLocation
) {
  expectValidLineBuffer(merge.base, sourceLocation: sourceLocation)
  expectValidLineBuffer(merge.a, sourceLocation: sourceLocation)
  expectValidLineBuffer(merge.b, sourceLocation: sourceLocation)

  var next = (base: 0, a: 0, b: 0)
  for block in merge.blocks {
    #expect(
      block.base.lines.lowerBound == next.base && block.a.lines.lowerBound == next.a
        && block.b.lines.lowerBound == next.b,
      "blocks are contiguous", sourceLocation: sourceLocation)
    #expect(
      !(block.base.isEmpty && block.a.isEmpty && block.b.isEmpty), "no empty block",
      sourceLocation: sourceLocation)

    var baseA = spansEqual(block.base, in: merge.base, block.a, in: merge.a, under: mode)
    var baseB = spansEqual(block.base, in: merge.base, block.b, in: merge.b, under: mode)
    var aB = spansEqual(block.a, in: merge.a, block.b, in: merge.b, under: mode)
    if mode == .ignoreLineEndings {
      // With -dl, equality is not transitive (see linesEqual), but the merge
      // grid combines the three pairwise diffs as if it were.
      (baseA, baseB, aB) = (baseA || baseB && aB, baseB || baseA && aB, aB || baseA && baseB)
    }

    let consistent =
      switch block.kind {
      case .unchanged: baseA && baseB
      case .changedInA: baseB && !baseA
      case .changedInB: baseA && !baseB
      case .changedInBoth: aB
      case .conflict: !aB
      }
    #expect(
      consistent, "\(block.kind) block under \(mode): \(block)", sourceLocation: sourceLocation)

    next = (block.base.lines.upperBound, block.a.lines.upperBound, block.b.lines.upperBound)
  }
  #expect(
    next == (merge.base.lineCount, merge.a.lineCount, merge.b.lineCount),
    "blocks cover all inputs", sourceLocation: sourceLocation)
}
