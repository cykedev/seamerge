import Foundation
import Testing

@testable import MergeEngine

/// `Merge` is built on `DiffMerge::NextChunk()`, an addition to the vendored
/// code. These tests check that its blocks describe exactly what Perforce's
/// original `DiffMerge::Read()` outputs for the same input.
@Suite("Consistency with DiffMerge::Read()")
struct ReadConsistencyTests {
  private func expectConsistent(
    base: Data, a: Data, b: Data, whitespace: Whitespace, strategy: MergeStrategy,
    sourceLocation: SourceLocation = #_sourceLocation
  ) throws {
    let merge = try Merge(base: base, a: a, b: b, whitespace: whitespace, strategy: strategy)
    let reference = try referenceMergeText(
      base: base, a: a, b: b, whitespace: whitespace, strategy: strategy)
    #expect(readStream(of: merge) == reference.text, sourceLocation: sourceLocation)
    #expect(merge.conflictCount == reference.conflictCount, sourceLocation: sourceLocation)
  }

  @Test("Every fixture, mode and strategy", arguments: Fixtures.mergeCases, Whitespace.allCases)
  func fixtures(name: String, whitespace: Whitespace) throws {
    let input = try Fixtures.triple(name)
    for strategy in MergeStrategy.allCases {
      try expectConsistent(
        base: input.base, a: input.a, b: input.b, whitespace: whitespace, strategy: strategy)
    }
  }

  /// Larger inputs with more edits reach the engine's extension of
  /// conflicts across several chunks.
  @Test("Random merges", arguments: Whitespace.allCases)
  func randomMerges(whitespace: Whitespace) throws {
    var generator = SplitMix64(seed: 2026)
    for round in 0..<400 {
      let input =
        round.isMultiple(of: 2)
        ? RandomMergeInput(using: &generator)
        : RandomMergeInput(maximumLines: 80, maximumEdits: 12, using: &generator)
      for strategy in MergeStrategy.allCases {
        try expectConsistent(
          base: input.base, a: input.a, b: input.b, whitespace: whitespace, strategy: strategy)
        let merge = try Merge(
          base: input.base, a: input.a, b: input.b, whitespace: whitespace, strategy: strategy)
        expectValidMerge(merge, under: whitespace)
      }
    }
  }
}
