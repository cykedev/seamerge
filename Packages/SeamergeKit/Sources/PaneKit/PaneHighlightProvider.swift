/// Supplies the runs within the lines of a block that differ from the other side, and the places
/// where the side removed text.
///
/// A pane asks only for the blocks it is about to draw, and asks for each block once until its
/// content or its provider changes.
@MainActor
package protocol PaneHighlightProvider: AnyObject {
  /// The changed runs of the block at `block` in the pane's blocks, as UTF-16 offsets into the
  /// pane's text, sorted and without overlap.
  ///
  /// A run of length zero marks a place where the side removed text: the pane draws a narrow
  /// bar there, in the color of the side.
  func highlights(forBlock block: Int) -> [Range<Int>]
}
