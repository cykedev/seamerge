import Foundation

/// The content of a pane with what showing it takes worked out beforehand, away from the main
/// actor: the rows of its text, and the text as a text view stores it.
///
/// Showing prepared content leaves the main actor only putting it in place, which for a text of
/// several megabytes is a matter of a millisecond rather than of tens of them.
public struct PreparedPaneContent: Sendable {
  /// What the pane shows.
  public let content: PaneContent

  /// The rows of the text with tabs of `tabWidth` columns.
  let grid: RowGrid

  /// The width of a tab in columns that the rows were found with.
  let tabWidth: Int

  /// The text of the content, stored in UTF-16 as a text view stores it.
  let storedText: String

  /// Prepares `content` for a pane whose tabs are `tabWidth` columns wide; best done away from
  /// the main actor, since it takes time in proportion to the text.
  public init(preparing content: PaneContent, tabWidth: Int) {
    self.content = content
    self.tabWidth = tabWidth
    storedText = Self.storedText(of: content.text)
    grid = RowGrid(text: content.text, tabWidth: tabWidth)
  }

  /// `text` as a string of Foundation, which hands its storage to the text view as it is, read
  /// from the UTF-8 of `text` without a copy in UTF-16 on the way.
  ///
  /// Foundation drops a byte order mark at the start of UTF-8, which the text keeps as its
  /// first character; such a text takes the way through UTF-16, so that the stored text has
  /// every character of the text and the rows find them where they are.
  private static func storedText(of text: String) -> String {
    guard !text.utf8.starts(with: [0xEF, 0xBB, 0xBF]) else {
      let units = Array(text.utf16)
      return NSString(characters: units, length: units.count) as String
    }
    var text = text
    return text.withUTF8 { utf8 in
      guard let start = utf8.baseAddress,
        let stored = NSString(bytes: start, length: utf8.count, encoding: NSUTF8StringEncoding)
      else { return NSString() as String }
      return stored as String
    }
  }
}
