import Foundation

/// The token-by-token differences between two short inputs, for
/// highlighting changes within lines.
///
/// Typically applied to the bytes of one changed ``Diff`` block or one pair
/// of lines. Tokens are compared byte for byte. The blocks cover both inputs
/// completely and in order, alternating between equal and changed runs of
/// tokens.
public struct TokenDiff: Sendable {
  public typealias BlockKind = Diff.BlockKind

  public struct Block: Sendable, Hashable {
    public let kind: BlockKind
    public let a: TokenSpan
    public let b: TokenSpan
  }

  public let a: TokenBuffer
  public let b: TokenBuffer
  public let blocks: [Block]

  /// Compares `a` and `b` token by token.
  public init(
    _ a: Data, _ b: Data, granularity: TokenGranularity = .characterClasses
  ) throws(EngineError) {
    let comparison = try TwoWayComparison(a, b, sequence: granularity.sequence)
    let bufferA = TokenBuffer(data: a, offsets: comparison.offsetsA)
    let bufferB = TokenBuffer(data: b, offsets: comparison.offsetsB)
    self.a = bufferA
    self.b = bufferB
    self.blocks = comparison.blocks.map { block in
      Block(
        kind: block.isEqual ? .equal : .changed,
        a: TokenSpan(tokens: block.a, in: bufferA),
        b: TokenSpan(tokens: block.b, in: bufferB))
    }
  }

  /// The changed blocks.
  public var changes: [Block] { blocks.filter { $0.kind == .changed } }

  /// Whether the inputs are byte-identical.
  public var isIdentical: Bool { !blocks.contains { $0.kind == .changed } }
}

/// An input of a ``TokenDiff`` together with the engine's split of it into
/// tokens.
public struct TokenBuffer: Sendable, Hashable {
  /// The input bytes.
  public let data: Data

  /// Byte offset where each token starts, followed by `data.count`.
  let offsets: [Int]

  init(data: Data, offsets: [Int]) {
    self.data = data.zeroBased
    self.offsets = offsets
  }

  /// The number of tokens.
  public var tokenCount: Int { offsets.count - 1 }

  /// The byte range of `tokens`.
  ///
  /// - Precondition: `tokens` lies within `0...tokenCount`.
  public func byteRange(tokens: Range<Int>) -> Range<Int> {
    offsets[tokens.lowerBound]..<offsets[tokens.upperBound]
  }

  /// The bytes of `tokens`.
  ///
  /// - Precondition: `tokens` lies within `0...tokenCount`.
  public func bytes(tokens: Range<Int>) -> Data {
    data.subdata(in: byteRange(tokens: tokens))
  }

  /// The bytes of one token.
  ///
  /// - Precondition: `index` lies within `0..<tokenCount`.
  public func token(_ index: Int) -> Data {
    bytes(tokens: index..<index + 1)
  }
}

/// A range of one input of a ``TokenDiff``, in tokens and in bytes.
public struct TokenSpan: Sendable, Hashable {
  /// The tokens, as zero-based indices.
  public let tokens: Range<Int>

  /// The bytes of ``tokens``, as offsets into the input.
  public let byteRange: Range<Int>

  init(tokens: Range<Int>, in buffer: TokenBuffer) {
    self.tokens = tokens
    self.byteRange = buffer.byteRange(tokens: tokens)
  }

  public var isEmpty: Bool { tokens.isEmpty }
}
