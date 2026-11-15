/// What lies under a click in a pane: the row on the grid and the block it belongs to.
public struct PaneHit: Sendable, Hashable {
  /// The row on the grid.
  public var row: Int

  /// The index of the block that the row belongs to, or `nil` if the row is unchanged.
  public var block: Int?

  /// Whether the click hit the arrow of a move in the gutter, which asks to go to the other end
  /// of the move; ``block`` is then the block of the arrow.
  public var isOnMoveArrow: Bool

  /// Creates a hit.
  public init(row: Int, block: Int?, isOnMoveArrow: Bool = false) {
    self.row = row
    self.block = block
    self.isOnMoveArrow = isOnMoveArrow
  }
}
