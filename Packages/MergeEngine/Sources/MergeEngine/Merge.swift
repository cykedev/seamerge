import CMergeEngine
public import Foundation

/// A three-way merge computed by the Perforce merge engine.
///
/// A is the incoming side (Perforce "theirs", leg 1), B the own side
/// (Perforce "yours", leg 2). The blocks cover base, A and B completely and in
/// order; each block records where it lies in all three inputs, so aligned
/// views and per-block choices can be built directly from them.
public struct Merge: Sendable {
  /// How A and B changed a region of the base.
  public enum BlockKind: Sendable, Hashable, CaseIterable {
    /// Base, A and B are equal under the comparison mode.
    case unchanged

    /// Only A changed this region.
    case changedInA

    /// Only B changed this region.
    case changedInB

    /// A and B made the same change.
    case changedInBoth

    /// A and B changed this region differently.
    case conflict
  }

  /// Where the merged text of a block comes from.
  public enum Source: Sendable, Hashable {
    case base
    case a
    case b

    /// A's lines followed by B's lines.
    case aThenB

    /// B's lines followed by A's lines.
    case bThenA
  }

  /// A region of the merge and where it lies in base, A and B.
  ///
  /// Any of the three runs may be empty, but not all of them.
  public struct Block: Sendable, Hashable {
    /// How A and B changed the region.
    public let kind: BlockKind

    /// The run in the base; empty where A, B or both inserted lines, and
    /// always empty with ``MergeStrategy/twoWay``.
    public let base: LineSpan

    /// The run in A.
    public let a: LineSpan

    /// The run in B.
    public let b: LineSpan

    /// The source used when no resolution is given, or `nil` for a conflict.
    ///
    /// A change made on one side only takes that side. Where B's text counts
    /// as equal to another side's (unchanged blocks and identical changes), B
    /// is taken, so that with a comparison mode other than
    /// ``Whitespace/exact`` the result keeps the own side's whitespace and
    /// line endings. This is the behavior `diffmerge.h` documents;
    /// `DiffMerge::Read()` itself outputs the base for unchanged blocks and A
    /// for identical changes.
    public var defaultSource: Source? {
      switch kind {
      case .unchanged, .changedInB, .changedInBoth: .b
      case .changedInA: .a
      case .conflict: nil
      }
    }
  }

  /// How ``result(markingConflicts:labels:resolutions:)`` writes a conflict.
  public enum ConflictStyle: Sendable, Hashable {
    /// B between `<<<<<<<` and `=======`, A between `=======` and `>>>>>>>`:
    /// the own side first, as Git writes it.
    case merge

    /// Like ``merge``, with the base between `|||||||` and `=======`.
    case diff3
  }

  /// The names written after the conflict markers.
  public struct ConflictLabels: Sendable, Hashable {
    /// Written after `>>>>>>>`, the marker that closes A's lines.
    public var a: String

    /// Written after `|||||||`, the marker that opens the base's lines in the
    /// ``ConflictStyle/diff3`` style.
    public var base: String

    /// Written after `<<<<<<<`, the marker that opens B's lines.
    public var b: String

    /// Creates labels for the three markers that carry one.
    public init(a: String = "A", base: String = "BASE", b: String = "B") {
      self.a = a
      self.base = base
      self.b = b
    }
  }

  /// A merged text and the part of it that each block produced.
  public struct Output: Sendable, Hashable {
    /// The merged bytes.
    public let data: Data

    /// The byte range of ``data`` produced by each block, in the order of
    /// ``Merge/blocks``.
    ///
    /// The ranges are contiguous and cover all of ``data``; a block that
    /// contributes no text has an empty range. The range of a conflict written
    /// with markers includes the markers.
    public let blockRanges: [Range<Int>]
  }

  /// The base, split into lines; empty with ``MergeStrategy/twoWay``, which
  /// ignores the base it is given.
  public let base: LineBuffer

  /// The incoming side, split into lines.
  public let a: LineBuffer

  /// The own side, split into lines.
  public let b: LineBuffer

  /// The blocks in input order; empty when all three inputs are empty.
  public let blocks: [Block]

  /// The line ending for text the merge inserts: the first one found in B, A
  /// or the base (in that order), or LF.
  private let lineEnding: Data

  /// Merges the changes from `base` to `a` and from `base` to `b`.
  public init(
    base: Data, a: Data, b: Data, whitespace: Whitespace = .exact,
    strategy: MergeStrategy = .optimal
  ) throws(EngineError) {
    var handle: OpaquePointer?
    let status = withBytes(base, a, b) { p0, l0, pa, la, pb, lb in
      me_merge_create(p0, l0, pa, la, pb, lb, whitespace.sequence, strategy.grid, &handle)
    }
    defer { me_merge_destroy(handle) }
    try check(status)

    func buffer(_ data: Data, _ side: me_merge_side) throws(EngineError) -> LineBuffer {
      var count = 0
      let pointer = me_merge_offsets(handle, side, &count)
      return LineBuffer(data: data, offsets: try offsets(pointer, count: count))
    }
    // The two-way strategy merges against an empty base.
    let bufferBase = try buffer(strategy == .twoWay ? Data() : base, ME_MERGE_SIDE_BASE)
    let bufferA = try buffer(a, ME_MERGE_SIDE_A)
    let bufferB = try buffer(b, ME_MERGE_SIDE_B)

    var count = 0
    let raw = elements(me_merge_blocks(handle, &count), count: count)
    var blocks: [Block] = []
    blocks.reserveCapacity(raw.count)
    for block in raw {
      blocks.append(
        Block(
          kind: try BlockKind(block.kind),
          base: LineSpan(lines: Int(block.base_start)..<Int(block.base_end), in: bufferBase),
          a: LineSpan(lines: Int(block.a_start)..<Int(block.a_end), in: bufferA),
          b: LineSpan(lines: Int(block.b_start)..<Int(block.b_end), in: bufferB)))
    }

    self.base = bufferBase
    self.a = bufferA
    self.b = bufferB
    self.blocks = blocks
    self.lineEnding = Self.lineEnding(in: [bufferB.data, bufferA.data, bufferBase.data])
  }

  /// The number of blocks of kind ``BlockKind/conflict``.
  public var conflictCount: Int { blocks.count { $0.kind == .conflict } }

  /// Whether any block is a conflict.
  public var hasConflicts: Bool { blocks.contains { $0.kind == .conflict } }

  /// The text `source` contributes for `block`.
  ///
  /// For ``Source/aThenB`` and ``Source/bThenA``, a line ending is inserted
  /// between the parts if the first one ends without one.
  public func text(of block: Block, from source: Source) -> Data {
    part(of: block, from: source).zeroBased
  }

  /// The text `source` contributes for `block`, as a slice of the input when
  /// it comes from one input, so that it is copied only into the result.
  private func part(of block: Block, from source: Source) -> Data {
    switch source {
    case .base: base.data[block.base.byteRange]
    case .a: a.data[block.a.byteRange]
    case .b: b.data[block.b.byteRange]
    case .aThenB: joined([part(of: block, from: .a), part(of: block, from: .b)]).data
    case .bThenA: joined([part(of: block, from: .b), part(of: block, from: .a)]).data
    }
  }

  /// The merged text, or `nil` if a conflict is left unresolved.
  ///
  /// A block whose text ends without a line ending, because it holds the last
  /// line of its input, gets one when more text follows, so that lines are
  /// never glued together.
  ///
  /// - Parameter resolutions: The source for each block index that should not
  ///   use its ``Block/defaultSource``. Every conflict needs an entry.
  public func result(resolutions: [Int: Source] = [:]) -> Output? {
    var parts: [Data] = []
    parts.reserveCapacity(blocks.count)
    for (index, block) in blocks.enumerated() {
      guard let source = resolutions[index] ?? block.defaultSource else { return nil }
      parts.append(part(of: block, from: source))
    }
    return joined(parts)
  }

  /// The merged text with conflict markers around every unresolved conflict.
  ///
  /// Line endings are inserted as in ``result(resolutions:)``.
  public func result(
    markingConflicts style: ConflictStyle,
    labels: ConflictLabels = ConflictLabels(),
    resolutions: [Int: Source] = [:]
  ) -> Output {
    var parts: [Data] = []
    parts.reserveCapacity(blocks.count)
    for (index, block) in blocks.enumerated() {
      if let source = resolutions[index] ?? block.defaultSource {
        parts.append(part(of: block, from: source))
        continue
      }
      var conflict = [marker("<<<<<<< \(labels.b)"), part(of: block, from: .b)]
      if style == .diff3 {
        conflict += [marker("||||||| \(labels.base)"), part(of: block, from: .base)]
      }
      conflict += [marker("======="), part(of: block, from: .a), marker(">>>>>>> \(labels.a)")]
      parts.append(joined(conflict).data)
    }
    return joined(parts)
  }

  private func marker(_ text: String) -> Data {
    Data(text.utf8) + lineEnding
  }

  /// Concatenates `parts`, appending `lineEnding` to every part that ends
  /// without a line ending and is followed by more text.
  private func joined(_ parts: [Data]) -> Output {
    let lastText = parts.lastIndex { !$0.isEmpty }
    var data = Data()
    data.reserveCapacity(parts.reduce(0) { $0 + $1.count + lineEnding.count })
    var ranges: [Range<Int>] = []
    ranges.reserveCapacity(parts.count)
    for (index, part) in parts.enumerated() {
      let start = data.count
      data.append(part)
      if let lastText, index < lastText, let last = part.last,
        last != UInt8(ascii: "\n"), last != UInt8(ascii: "\r")
      {
        data.append(lineEnding)
      }
      ranges.append(start..<data.count)
    }
    return Output(data: data, blockRanges: ranges)
  }

  /// The line ending of the first input that has one: CRLF or LF if it
  /// contains a line feed, otherwise CR if it contains a carriage return.
  private static func lineEnding(in inputs: [Data]) -> Data {
    let lf = UInt8(ascii: "\n")
    let cr = UInt8(ascii: "\r")
    for input in inputs {
      if let index = input.firstIndex(of: lf) {
        return index > input.startIndex && input[index - 1] == cr ? Data([cr, lf]) : Data([lf])
      }
      if input.contains(cr) {
        return Data([cr])
      }
    }
    return Data([lf])
  }
}

extension Merge.BlockKind {
  init(_ kind: me_merge_kind) throws(EngineError) {
    switch kind {
    case ME_MERGE_UNCHANGED: self = .unchanged
    case ME_MERGE_CHANGED_A: self = .changedInA
    case ME_MERGE_CHANGED_B: self = .changedInB
    case ME_MERGE_CHANGED_BOTH: self = .changedInBoth
    case ME_MERGE_CONFLICT: self = .conflict
    default: throw .internalFailure
    }
  }
}
