/// What the rows of a block show on one pane, which decides how they are tinted.
///
/// The style says what the rows are, not which color they get; the theme picks the color, so
/// that every pane tints the same kind of row the same way.
package enum BlockStyle: Sendable, Hashable {
  /// Rows that no side changed, and rows of the side that kept the text that the other side
  /// changed. They stay on the text background.
  case unchanged
  /// Rows tinted in the color of a role: on A or B the change that side made, on the base pane
  /// the base of a conflict that is still open, in the result the text taken from a side.
  case tinted(ColorRole)
  /// Rows of the base pane that a side changed.
  case original
  /// Rows of the result where both sides made the same change.
  case combined
  /// Rows of the result that were typed by hand.
  case handwritten
}
