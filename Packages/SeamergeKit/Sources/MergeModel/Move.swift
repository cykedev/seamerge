/// A run of lines that left one place and arrived at another, unchanged under the comparison
/// mode.
///
/// In a comparison, the lines leave A and arrive in B. In a merge, a side removed lines of the
/// base in one block and added the same lines in another; both ends lie in that side.
public struct Move: Sendable, Hashable {
  /// One of the two places of a move.
  public struct End: Sendable, Hashable {
    /// The ID of the block the end lies in.
    public let block: Int

    /// The input whose pane shows the end.
    public let role: Role

    /// The moved lines in the input of ``role``, as zero-based indices.
    ///
    /// At the source of a move in a merge, the side no longer has the lines; the range is the
    /// empty one where they were.
    public let lines: Range<Int>
  }

  /// The place the lines left.
  public let source: End

  /// The place the lines arrived at.
  public let destination: End

  /// The move read the other way round: the lines leave its destination and arrive at its
  /// source.
  func reversed() -> Move {
    Move(source: destination, destination: source)
  }
}
