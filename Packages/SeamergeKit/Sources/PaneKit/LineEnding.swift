/// How a line of the file ends, which a pane shows among the invisible characters.
///
/// The text of a pane separates its rows with line feeds whatever the file uses, so the pane
/// learns the real ending of each line from its content.
public enum LineEnding: Sendable, Hashable, CaseIterable {
  /// A line feed, as on macOS and Linux; shown as `¬`.
  case lineFeed
  /// A carriage return followed by a line feed, as on Windows; shown as `¤¬`.
  case carriageReturnLineFeed
  /// A carriage return alone, as in old Mac files; shown as `¤`.
  case carriageReturn
  /// No ending: the last line of a file without a final line break, or a filler row.
  case none

  /// The invisible characters that stand for the ending.
  ///
  /// The code font has `¤` in the width of a cell; the symbol for a carriage return, `␍`, comes
  /// from a fallback font as two letters too small to read at the size of code.
  var symbol: String {
    switch self {
    case .lineFeed: "¬"
    case .carriageReturnLineFeed: "¤¬"
    case .carriageReturn: "¤"
    case .none: ""
    }
  }
}
