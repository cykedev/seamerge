/// A block as the overview bar marks it: where it lies, what it holds, and on which side of the
/// bar its mark sits.
package struct OverviewMark: Sendable, Hashable {
  /// The part of the overview bar's width that a mark covers.
  ///
  /// The place is the second carrier of what the color says, so that A and B differ without
  /// color too.
  package enum Placement: Sendable, Hashable {
    /// The leading two thirds, for changes of A.
    case leading
    /// The trailing two thirds, for changes of B.
    case trailing
    /// The full width, for conflicts, open or resolved.
    case fullWidth
  }

  /// The rows of the block on the grid of the pane that the bar scrolls.
  package var rows: Range<Int>

  /// What the rows hold, which decides the color of the mark; a block whose style is the
  /// conflict tint is an open conflict.
  package var style: BlockStyle

  /// The part of the bar's width that the mark covers.
  package var placement: Placement

  /// The index of the block, which the bar reports when its mark is clicked.
  package var block: Int

  /// What VoiceOver says for the mark, such as the kind of change and its lines.
  package var accessibilityLabel: String

  /// Creates a mark.
  package init(
    rows: Range<Int>, style: BlockStyle, placement: Placement, block: Int,
    accessibilityLabel: String
  ) {
    self.rows = rows
    self.style = style
    self.placement = placement
    self.block = block
    self.accessibilityLabel = accessibilityLabel
  }

  /// Whether the mark stands for a conflict that still needs a decision.
  var isOpenConflict: Bool { style == .tinted(.conflict) }
}
