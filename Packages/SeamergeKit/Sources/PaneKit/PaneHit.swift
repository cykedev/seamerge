/// What lies under a click in a pane: the row on the grid and the block it belongs to.
public struct PaneHit: Sendable, Hashable {
  /// The row on the grid.
  public var row: Int

  /// The index of the block that the row belongs to, or `nil` if the row is unchanged.
  public var block: Int?

  /// Creates a hit.
  public init(row: Int, block: Int?) {
    self.row = row
    self.block = block
  }
}
