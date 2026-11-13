import AppKit
import PaneKit

/// Rows of code-like text for panes that have to scroll.
enum CodeRows {
  /// The height of the text of `pane` when it shows `rows` rows: their height, but at least the
  /// height of the view, which the text always fills.
  @MainActor
  static func textHeight(ofRows rows: Int, in pane: PaneView) -> CGFloat {
    let visible = pane.documentView.enclosingScrollView?.contentView.bounds.height ?? 0
    return max(CGFloat(rows) * pane.theme.rowHeight, visible)
  }

  /// `count` rows, each a line of `length` characters that names its row, with `blocks`.
  static func content(count: Int, length: Int = 60, blocks: [PaneBlock] = []) -> PaneContent {
    PaneContent(
      text: (0..<count).map { line(row: $0, length: length) }.joined(separator: "\n"),
      lineNumbers: (0..<count).map(Int32.init), blocks: blocks)
  }

  /// The line of `row`: its number, then filler words up to `length` characters.
  static func line(row: Int, length: Int) -> String {
    var line = "let row\(row) = value"
    while line.count < length {
      line += " + next"
    }
    return String(line.prefix(length))
  }

  /// The UTF-16 offset at which `row` starts in a content of rows of `length` characters.
  static func start(ofRow row: Int, length: Int = 60) -> Int {
    row * (length + 1)
  }
}
