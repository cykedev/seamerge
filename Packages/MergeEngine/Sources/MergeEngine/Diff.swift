import Foundation

/// The line-by-line differences between two inputs, computed by the
/// Perforce diff engine.
///
/// The blocks cover both inputs completely and in order, alternating between
/// equal and changed runs of lines. Inputs are arbitrary bytes; no text
/// encoding is assumed. For changes within lines, see ``TokenDiff``.
public struct Diff: Sendable {
  public enum BlockKind: Sendable, Hashable {
    /// The runs are equal. In a line diff with a comparison mode other than
    /// ``Whitespace/exact``, their bytes may still differ.
    case equal

    /// The run in A was replaced by the run in B. Either side may be empty.
    case changed
  }

  public struct Block: Sendable, Hashable {
    public let kind: BlockKind
    public let a: Span
    public let b: Span

    /// Whether the block adds lines that are only in B.
    public var isInsertion: Bool { kind == .changed && a.isEmpty }

    /// Whether the block removes lines that are only in A.
    public var isDeletion: Bool { kind == .changed && b.isEmpty }
  }

  public let a: LineBuffer
  public let b: LineBuffer
  public let blocks: [Block]

  /// Compares `a` and `b` line by line.
  public init(_ a: Data, _ b: Data, whitespace: Whitespace = .exact) throws(EngineError) {
    let comparison = try TwoWayComparison(a, b, sequence: whitespace.sequence)
    let bufferA = LineBuffer(data: a, offsets: comparison.offsetsA)
    let bufferB = LineBuffer(data: b, offsets: comparison.offsetsB)
    self.a = bufferA
    self.b = bufferB
    self.blocks = comparison.blocks.map { block in
      Block(
        kind: block.isEqual ? .equal : .changed,
        a: Span(lines: block.a, in: bufferA),
        b: Span(lines: block.b, in: bufferB))
    }
  }

  /// The changed blocks.
  public var changes: [Block] { blocks.filter { $0.kind == .changed } }

  /// Whether the inputs are equal under the comparison mode.
  public var isIdentical: Bool { !blocks.contains { $0.kind == .changed } }
}
