/// Supplies the stretches of the lines of a pane that are colored by their syntax.
///
/// A pane asks only for the lines of the rows it is about to draw, and asks again for rows it
/// is told have changed (``PaneView/syntaxDidChange(inRows:)``). It leaves the stretches within
/// the changed runs of a block and within previews in their own colors: the change takes
/// precedence over the syntax.
@MainActor
package protocol PaneSyntaxProvider: AnyObject {
  /// The tokens of `line`, the line number that the pane's content gives its rows, in order and
  /// without overlap, in UTF-16 offsets from the start of the line.
  ///
  /// A line the provider does not know yet, or no longer, has no tokens.
  func tokens(inLine line: Int) -> [PaneToken]
}
