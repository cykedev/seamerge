/// A change of a pane's text: a range of the text and the text that replaces it.
public struct PaneEdit: Sendable, Hashable {
  /// The replaced range, in UTF-16 code units.
  public var range: Range<Int>

  /// The text that replaces the range.
  public var text: String

  /// Creates an edit that replaces `range` by `text`.
  public init(range: Range<Int>, text: String) {
    self.range = range
    self.text = text
  }
}
