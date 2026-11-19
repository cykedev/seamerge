/// What lies under a click in a pane: the row on the grid and the block it belongs to.
package struct PaneHit: Sendable, Hashable {
  /// The row on the grid.
  package var row: Int

  /// The index of the block that the row belongs to, or `nil` if the row is unchanged.
  package var block: Int?

  /// Whether the click hit the arrow of a move in the gutter, which asks to go to the other end
  /// of the move; ``block`` is then the block of the arrow.
  package var isOnMoveArrow: Bool

  /// Creates a hit.
  package init(row: Int, block: Int?, isOnMoveArrow: Bool = false) {
    self.row = row
    self.block = block
    self.isOnMoveArrow = isOnMoveArrow
  }
}
