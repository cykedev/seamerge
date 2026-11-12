import Foundation
import MergeEngine

/// The bridge to the diff and merge engine, and the only place that knows its types.
///
/// Everything the engine reports is translated into the types of this module here, so that a
/// change of the engine's interface stays within this file.
enum EngineAdapter {
  /// The blocks of a comparison and the engine's split of each input into lines.
  struct Comparison {
    /// The blocks in input order.
    var blocks: [Block]

    /// The byte offset where each line of an input starts, followed by its byte count.
    ///
    /// Inputs that take no part, such as the base of a comparison of two files, are missing.
    var lineStarts: [Role: [Int]]
  }

  /// The runs of tokens in which two texts differ.
  struct TokenComparison {
    /// A run of tokens in the first text and the run in the second text it was replaced by;
    /// either may be empty.
    struct Run {
      /// The bytes of the run in the first text.
      var first: Range<Int>

      /// The bytes of the run in the second text.
      var second: Range<Int>

      /// The number of tokens in both runs together.
      var tokenCount: Int
    }

    /// The number of tokens in both texts together.
    var tokenCount: Int

    /// The changed runs, in text order.
    var changedRuns: [Run]
  }

  /// Merges the changes from the base to A and from the base to B, or merges A and B as if the
  /// base were empty when there is none.
  static func merge(
    base: Data?, a: Data, b: Data, options: ComparisonOptions
  ) throws(MergeModelError) -> Comparison {
    let merge: Merge
    do {
      merge = try Merge(
        base: base ?? Data(), a: a, b: b, whitespace: Whitespace(options.mode),
        strategy: base == nil ? .twoWay : MergeEngine.MergeStrategy(options.strategy))
    } catch {
      throw MergeModelError(error)
    }
    var lineStarts = [Role.a: lineStarts(of: merge.a), .b: lineStarts(of: merge.b)]
    if base != nil {
      lineStarts[.base] = Self.lineStarts(of: merge.base)
    }
    let blocks = merge.blocks.enumerated().map { index, block in
      Block(
        id: index, kind: Block.Kind(block.kind), base: block.base.lines, a: block.a.lines,
        b: block.b.lines)
    }
    return Comparison(blocks: blocks, lineStarts: lineStarts)
  }

  /// Compares two files line by line; the older file becomes A, the newer B.
  static func diff(
    old: Data, new: Data, mode: ComparisonMode
  ) throws(MergeModelError) -> Comparison {
    let diff: Diff
    do {
      diff = try Diff(old, new, whitespace: Whitespace(mode))
    } catch {
      throw MergeModelError(error)
    }
    let blocks = diff.blocks.enumerated().map { index, block in
      Block(
        id: index, kind: block.kind == .equal ? .unchanged : .changed, base: 0..<0,
        a: block.a.lines, b: block.b.lines)
    }
    return Comparison(
      blocks: blocks, lineStarts: [.a: lineStarts(of: diff.a), .b: lineStarts(of: diff.b)])
  }

  /// Compares two texts in runs of one character class: letters, digits and all non-ASCII
  /// bytes; spaces and other whitespace; punctuation; line endings.
  ///
  /// Every run starts and ends at the start of a Unicode scalar when both texts are valid UTF-8,
  /// because the bytes of a multi-byte scalar all belong to the same class.
  static func compareTokens(
    _ first: Data, _ second: Data
  ) throws(MergeModelError) -> TokenComparison {
    let tokens: TokenDiff
    do {
      tokens = try TokenDiff(first, second, granularity: .characterClasses)
    } catch {
      throw MergeModelError(error)
    }
    let changedRuns = tokens.changes.map { change in
      TokenComparison.Run(
        first: change.a.byteRange, second: change.b.byteRange,
        tokenCount: change.a.tokens.count + change.b.tokens.count)
    }
    return TokenComparison(
      tokenCount: tokens.a.tokenCount + tokens.b.tokenCount, changedRuns: changedRuns)
  }

  /// The byte offset where each line starts, followed by the byte count.
  ///
  /// The buffer does not publish its offsets, but the empty range before each line starts at
  /// them.
  private static func lineStarts(of buffer: LineBuffer) -> [Int] {
    (0...buffer.lineCount).map { buffer.byteRange(lines: $0..<$0).lowerBound }
  }
}

extension Whitespace {
  fileprivate init(_ mode: ComparisonMode) {
    self =
      switch mode {
      case .exact: .exact
      case .ignoreLineEndings: .ignoreLineEndings
      case .ignoreWhitespaceAmount: .ignoreAmount
      case .ignoreAllWhitespace: .ignoreAll
      }
  }
}

extension MergeEngine.MergeStrategy {
  fileprivate init(_ strategy: MergeModel.MergeStrategy) {
    self =
      switch strategy {
      case .optimal: .optimal
      case .guarded: .guarded
      case .diff3: .diff3
      case .guardedDiff3: .guardedDiff3
      }
  }
}

extension Block.Kind {
  fileprivate init(_ kind: Merge.BlockKind) {
    self =
      switch kind {
      case .unchanged: .unchanged
      case .changedInA: .changedInA
      case .changedInB: .changedInB
      case .changedInBoth: .changedInBoth
      case .conflict: .conflict
      }
  }
}

extension MergeModelError {
  fileprivate init(_ error: EngineError) {
    self =
      switch error {
      case .inputTooLarge: .inputTooLarge
      case .outOfMemory: .outOfMemory
      case .internalFailure: .comparisonFailed
      }
  }
}
