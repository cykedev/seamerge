/// A region of a session and the lines it covers in each input.
///
/// The blocks of a session cover every input completely and in order. Within a block, the
/// ranges of the inputs may differ in length, and any of them may be empty, but not all.
public struct Block: Sendable, Hashable, Identifiable {
  /// How the inputs differ in a block.
  public enum Kind: Sendable, Hashable, CaseIterable {
    /// All inputs are equal under the comparison mode.
    case unchanged

    /// Only A changed this region of the base.
    case changedInA

    /// Only B changed this region of the base.
    case changedInB

    /// A and B made the same change to this region of the base.
    case changedInBoth

    /// A and B changed this region of the base differently.
    case conflict

    /// The two files of a comparison differ in this region.
    case changed
  }

  /// The position of the block in the session, counted from 0.
  public let id: Int

  /// How the inputs differ.
  public let kind: Kind

  /// The lines of the base, as zero-based indices; empty in a comparison and in a merge without
  /// a base.
  public let base: Range<Int>

  /// The lines of A, as zero-based indices.
  public let a: Range<Int>

  /// The lines of B, as zero-based indices.
  public let b: Range<Int>

  /// The lines the block covers in the input of `role`.
  public func lines(in role: Role) -> Range<Int> {
    switch role {
    case .base: base
    case .a: a
    case .b: b
    }
  }

  /// The number of rows the block takes on the row grid: as many as its longest range has lines.
  var rowCount: Int { max(base.count, a.count, b.count) }
}
