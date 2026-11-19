/// A change of a pane's text: a range of the text and the text that replaces it.
package struct PaneEdit: Sendable, Hashable {
  /// The replaced range, in UTF-16 code units.
  package var range: Range<Int>

  /// The text that replaces the range.
  package var text: String

  /// Creates an edit that replaces `range` by `text`.
  package init(range: Range<Int>, text: String) {
    self.range = range
    self.text = text
  }
}
